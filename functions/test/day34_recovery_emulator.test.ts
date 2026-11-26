import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import { FirestoreAuditWriter } from "../src/audit";
import { FirestoreAccountService } from "../src/account_service";
import { HostedWorkflowDelivery } from "../src/workflow_delivery";
import { reconcileAccountAuth } from "../src/account_auth_recovery";
import { PlanAuditContract, planEvents } from "../src/plan_audit_contract";
import { FirestorePrivacyAcceptanceStore, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { FirestorePrivacyPreferencesRepository } from "../src/firestore_privacy_preferences_repository";
import { FirestoreClientIntakeRepository } from "../src/firestore_client_intake_repository";
import { PrivateRecordAuthorizationError } from "../src/nutrition_record_access_service";

const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
(authHost && firestoreHost ? describe : describe.skip)("Day 3 recovery and Day 4 plan contracts", () => {
  let app: App, auth: Auth, db: Firestore, accounts: FirestoreAccountService, audit: FirestoreAuditWriter;
  const actor = { uid: "admin", role: "admin" as const, roleRevision: 0, displayName: "Admin" };
  let now: number;
  before(() => {
    assert(/^(localhost|127\.0\.0\.1):\d+$/.test(authHost!));
    assert(/^(localhost|127\.0\.0\.1):\d+$/.test(firestoreHost!));
    app = initializeApp({ projectId: "demo-fitnep" }, "day34-recovery");
    auth = getAuth(app); db = getFirestore(app); accounts = new FirestoreAccountService(db, auth); audit = new FirestoreAuditWriter(db);
  });
  beforeEach(async () => {
    const reset = await Promise.all([
      fetch(`http://${authHost}/emulator/v1/projects/demo-fitnep/accounts`, { method: "DELETE" }),
      fetch(`http://${firestoreHost}/emulator/v1/projects/demo-fitnep/databases/(default)/documents`, { method: "DELETE" }),
    ]);
    assert(reset.every(result => result.ok));
    for (const [uid, role] of [["admin", "admin"], ["client", "client"], ["other-client", "client"], ["dietitian", "dietitian"], ["replacement", "dietitian"]] as const) {
      await auth.createUser({ uid, email: `${uid}@fitnep.test`, emailVerified: true });
      await auth.setCustomUserClaims(uid, { role });
      await accounts.provision(await auth.getUser(uid));
    }
    now = Date.now() + 1000;
    await db.doc("client_assignments/client").set({ active: true, client_id: "client", dietitian_id: "dietitian", version: 1,
      assigned_at: new Date(now).toISOString(), assigned_by_id: "admin", team_member_ids: [] });
    await db.doc("client_intakes/client").set({ client_id: "client", version: 1, status: "submitted", allergies: ["Private allergy"] });
  });
  after(() => deleteApp(app));

  async function enqueue() {
    let id = "";
    await db.runTransaction(async tx => {
      id = audit.appendWithEvent(tx, { actor, action: "client.assigned", targetType: "assignment", targetId: "client", clientId: "client",
        dietitianId: "dietitian", version: 1, outcome: "succeeded", operationId: "assign-v1", correlationId: "request-1" }, "client.assigned");
    });
    return id;
  }

  it("restart after commitment delivers assignment and available intake exactly once", async () => {
    const id = await enqueue();
    assert.equal((await db.collection("notifications").get()).size, 0);
    assert.equal(await new HostedWorkflowDelivery(db, () => now).drain(), 1);
    assert.equal((await db.collection("notifications").get()).size, 2);
    const immutable = (await db.doc(`workflow_outbox/${id}`).get()).data();
    await db.doc(`outbox_deliveries/${id}`).update({ state: "retry", next_attempt_at: Timestamp.fromMillis(now) });
    assert.equal(await new HostedWorkflowDelivery(db, () => now).drain(), 1);
    assert.equal((await db.collection("notifications").get()).size, 2);
    assert.equal((await db.collection("outbox_handler_receipts").get()).size, 1);
    assert.deepEqual((await db.doc(`workflow_outbox/${id}`).get()).data(), immutable);
    const previews = JSON.stringify((await db.collection("notifications").get()).docs.map(doc => doc.data()));
    assert(!previews.includes("Private allergy"));
  });

  it("a crashed lease is reclaimed, while the old team is never notified after reassignment", async () => {
    const id = await enqueue();
    await db.doc(`outbox_deliveries/${id}`).update({ state: "processing", lease_id: "crashed", next_attempt_at: Timestamp.fromMillis(now + 60_000) });
    assert.equal(await new HostedWorkflowDelivery(db, () => now).drain(), 0);
    await db.doc("client_assignments/client").update({ dietitian_id: "replacement", version: 2 });
    now += 60_001;
    assert.equal(await new HostedWorkflowDelivery(db, () => now).drain(), 1);
    assert.equal((await db.collection("notifications").get()).size, 0);
    assert.equal((await db.doc(`outbox_handler_receipts/${id}`).get()).get("result"), "superseded");
  });

  it("a failed transaction leaves no mutation, audit or delivery to fabricate success", async () => {
    await assert.rejects(db.runTransaction(async tx => {
      tx.create(db.doc("_day34_tests/rolled-back"), { decision: "accepted" });
      audit.appendWithEvent(tx, { actor, action: "client.assigned", targetType: "assignment", targetId: "client", clientId: "client",
        dietitianId: "dietitian", version: 1, outcome: "succeeded", operationId: "rolled-back", correlationId: "rollback" }, "client.assigned");
      throw new Error("Crash before commit");
    }));
    assert.equal((await db.doc("_day34_tests/rolled-back").get()).exists, false);
    assert.equal((await db.collection("workflow_outbox").get()).size, 0);
    assert.equal((await db.collection("audit_events").where("action", "==", "client.assigned").get()).size, 0);
  });

  it("external Auth failure retains a requested operation, then recovery completes once", async () => {
    await accounts.change(actor, "dietitian", { role: "staff" });
    const operations = await db.collection("account_auth_operations").get();
    assert.equal(operations.size, 1);
    const failing = { getUser: () => { throw new Error("Auth offline"); } } as unknown as Auth;
    assert.equal(await reconcileAccountAuth(failing, db), 0);
    assert.equal((await operations.docs[0]!.ref.get()).get("state"), "requested");
    assert.equal(await reconcileAccountAuth(auth, db), 1);
    assert.equal((await auth.getUser("dietitian")).customClaims?.role, "staff");
    assert.equal((await operations.docs[0]!.ref.get()).get("state"), "completed");
    assert.equal(await reconcileAccountAuth(auth, db), 0);
    assert.equal((await db.collection("audit_events").where("action", "==", "account.auth_synchronized").get()).size, 1);
  });

  it("all six trusted plan event fixtures retain actors, server times and versions without clinical data", async () => {
    const contract = new PlanAuditContract(db);
    const statuses = ["draft", "submitted", "returned", "approved", "published", "draft"];
    for (const [index, event] of planEvents.entries()) {
      const version = event === "revised" ? 2 : 1;
      const operationId = `plan-${event}`;
      await db.doc(`diet_plans/plan-1/versions/${version}`).set({ plan_id: "plan-1", client_id: "client", dietitian_id: "dietitian",
        version, status: statuses[index], last_event: event, last_actor_id: actor.uid, operation_id: operationId, meals: "Private plan content" });
      const append = () => db.runTransaction(tx => contract.append(tx, actor, { planId: "plan-1", version, event, operationId, correlationId: operationId }));
      await append(); await append();
    }
    const events = await db.collection("audit_events").where("target_type", "==", "plan").get();
    assert.equal(events.size, 6);
    assert.deepEqual(events.docs.map(doc => doc.get("action")).sort(), planEvents.map(event => `plan.${event}`).sort());
    for (const event of events.docs) {
      assert.equal(event.get("actor_id"), "admin"); assert(event.get("occurred_at") instanceof Timestamp);
      assert.equal(event.get("version"), event.get("action") === "plan.revised" ? 2 : 1);
    }
    assert(!JSON.stringify(events.docs.map(doc => doc.data())).includes("Private plan content"));
    await assert.rejects(db.runTransaction(tx => contract.append(tx, { uid: "client", role: "client" }, {
      planId: "plan-1", version: 2, event: "revised", operationId: "plan-revised", correlationId: "forged" })), /permission/i);
  });

  it("merged intake reads/reviews honor consent, assignment, ownership and stale versions", async () => {
    const repository = new FirestoreClientIntakeRepository(db);
    const dietitian = { uid: "dietitian", role: "dietitian" as const, roleRevision: 0 };
    await assert.rejects(repository.getForAssignedDietitian("client", dietitian.uid, { actor: dietitian, correlationId: "denied" }), PrivateRecordAuthorizationError);
    await new FirestorePrivacyAcceptanceStore(db).recordForClient("client", { age: 21, privacy_policy_accepted: true, privacy_policy_version: privacyPolicyVersion });
    await new FirestorePrivacyPreferencesRepository(db).updateSharing("client", { shareNutritionRecords: true });
    const intake = await repository.getForAssignedDietitian("client", dietitian.uid, { actor: dietitian, correlationId: "allowed" });
    assert.equal(intake.version, 1);
    await assert.rejects(repository.updateReviewForAssignedDietitian("client", dietitian.uid,
      { action: "reviewed", status: "reviewed", note: null, expectedVersion: 2 }, { actor: dietitian, correlationId: "stale" }));
    await repository.updateReviewForAssignedDietitian("client", dietitian.uid,
      { action: "missing_information", status: "information_requested", note: "Private request", expectedVersion: 1 }, { actor: dietitian, correlationId: "review" });
    const savedIntake = await db.doc("client_intakes/client").get();
    assert.equal(savedIntake.get("status"), "information_requested");
    assert.equal(savedIntake.get("review_note"), "Private request");
    assert.equal(savedIntake.get("reviewed_by_id"), "dietitian");
    assert.equal((await db.collection("intake_review_history").get()).size, 1);
    assert.equal((await db.collection("workflow_outbox").get()).size, 1);
    assert.equal(await new HostedWorkflowDelivery(db, () => now).drain(), 1);
    const clientNotifications = await db.collection("notifications")
      .where("recipient_id", "==", "client").get();
    assert.equal(clientNotifications.size, 1);
    assert.equal(clientNotifications.docs[0]!.get("type"), "intake");
    assert.equal(clientNotifications.docs[0]!.get("reference_id"), "client");
    assert.equal(clientNotifications.docs[0]!.get("title"), "Intake information requested");
    assert.match(clientNotifications.docs[0]!.get("message"), /additional or clearer information/i);
    assert.equal((await db.collection("notifications")
      .where("recipient_id", "==", "other-client").get()).size, 0);
    const owner = await repository.getForOwner({ uid: "client", role: "client", roleRevision: 0 }, "own");
    assert.equal(owner.review.note, "Private request");
    await db.doc("client_assignments/client").update({ dietitian_id: "replacement", version: 2 });
    await assert.rejects(repository.getForAssignedDietitian("client", dietitian.uid, { actor: dietitian, correlationId: "old-team" }), PrivateRecordAuthorizationError);
    assert(!JSON.stringify((await db.collection("audit_events").get()).docs.map(doc => doc.data())).includes("Private request"));
  });
});
