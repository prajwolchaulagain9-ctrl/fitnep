import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import request from "supertest";
import { FirestoreAuditWriter } from "../src/audit";
import { FirestoreAccountService } from "../src/account_service";
import { FirebaseAuthVerifier } from "../src/auth";
import { ClientIntakeService } from "../src/client_intake_service";
import { createNotificationApp } from "../src/http_app";
import { HostedWorkflowDelivery } from "../src/workflow_delivery";
import { reconcileAccountAuth } from "../src/account_auth_recovery";
import { PlanAuditContract, planEvents } from "../src/plan_audit_contract";
import { FirestorePrivacyAcceptanceStore, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { FirestorePrivacyPreferencesRepository } from "../src/firestore_privacy_preferences_repository";
import { FirestoreClientIntakeRepository } from "../src/firestore_client_intake_repository";
import { PrivateRecordAuthorizationError } from "../src/nutrition_record_access_service";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

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
    assert.equal((await db.collection("intake_review_history").get()).size, 1);
    assert.equal((await db.collection("workflow_outbox").get()).size, 1);
    const owner = await repository.getForOwner({ uid: "client", role: "client", roleRevision: 0 }, "own");
    assert.equal(owner.review.note, "Private request");
    await db.doc("client_assignments/client").update({ dietitian_id: "replacement", version: 2 });
    await assert.rejects(repository.getForAssignedDietitian("client", dietitian.uid, { actor: dietitian, correlationId: "old-team" }), PrivateRecordAuthorizationError);
    assert(!JSON.stringify((await db.collection("audit_events").get()).docs.map(doc => doc.data())).includes("Private request"));
  });

  it("resumes verified owner drafts without exposing them to the assigned dietitian", async () => {
    const api = request(createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(accounts),
      notificationRepository: new InMemoryNotificationRepository(),
      clientIntakeService: new ClientIntakeService(new FirestoreClientIntakeRepository(db)),
    }));
    const path = "/intakes/me/draft";
    const [owner, other, dietitian] = await Promise.all(
      ["client", "other-client", "dietitian"].map(uid => intakeTestToken(auth, uid)),
    );
    const save = (payload: object) => api.put(path).auth(owner!, { type: "bearer" }).send(payload);
    const load = (token: string) => api.get(path).auth(token, { type: "bearer" });
    const input = {
      expected_client_id: "client",
      expected_version: 1,
      expected_draft_revision: 0,
      guardian_consent_confirmed: false,
      answers: { age: "17", weight_kg: "62.5", allergies: "Synthetic draft allergy" },
    };
    await load(owner!).expect(403);

    const privacy = new FirestorePrivacyAcceptanceStore(db);
    for (const uid of ["client", "other-client"]) {
      await privacy.recordForClient(uid, {
        age: 21, privacy_policy_accepted: true, privacy_policy_version: privacyPolicyVersion,
      });
    }
    await load(dietitian!).expect(403);
    await api.put(path).auth(other!, { type: "bearer" }).send(input).expect(403);
    await save(input).expect(409);
    await db.doc("customer_purchases/client/purchases/intake-membership").set({
      purchased_at: Timestamp.fromMillis(now - 60_000),
      expires_at: Timestamp.fromMillis(now + 86_400_000),
    });
    await save({ ...input, answers: { ...input.answers, weight_kg: "0" } }).expect(400);
    await save(input).expect(400);
    const draft = db.doc("client_intakes/client/private/draft");
    assert.equal((await draft.get()).exists, false);

    const acceptance = db.doc("privacy_acceptances/client");
    const before = (await acceptance.get()).get("accepted_at") as Timestamp;
    const confirmed = { ...input, guardian_consent_confirmed: true };
    const saved = await save(confirmed).expect(200);
    const replay = await save(confirmed).expect(200);
    assert.equal(saved.body.data.draft_revision, 1);
    assert.equal(replay.body.data.draft_revision, 1);
    assert.equal(saved.body.data.guardian_consent_confirmed, true);
    assert.equal((await draft.get()).get("client_id"), "client");
    assert((await draft.get()).get("updated_at") instanceof Timestamp);
    const policy = await acceptance.get();
    assert(before.isEqual(policy.get("accepted_at")));
    assert(policy.get("guardian_consent_confirmed_at") instanceof Timestamp);

    const resumed = await load(owner!).expect("Cache-Control", "no-store").expect(200);
    assert.deepEqual(resumed.body.data.answers, input.answers);
    assert.equal((await load(other!).expect(200)).body.data.answers.weight_kg, undefined);
    await auth.updateUser("other-client", { emailVerified: false });
    await load(await intakeTestToken(auth, "other-client")).expect(403);
    await save({ ...confirmed, answers: { ...input.answers, weight_kg: "63" } }).expect(409);
    await new FirestorePrivacyPreferencesRepository(db).updateSharing("client", { shareNutritionRecords: true });
    const team = await api.get("/dietitian/assigned-clients/client/intake")
      .auth(dietitian!, { type: "bearer" }).expect(200);
    assert.deepEqual(team.body.data.intake.allergies, ["Private allergy"]);
    const direct = await fetch(
      `http://${firestoreHost}/v1/projects/demo-fitnep/databases/(default)/documents/${draft.path}`,
      { headers: { Authorization: `Bearer ${owner}` } },
    );
    assert.equal(direct.status, 403);
    const auditTrail = await db.collection("audit_events").get();
    assert(auditTrail.docs.some(doc => doc.get("target_id") === "client/intakes/draft"));
    assert(!JSON.stringify(auditTrail.docs.map(doc => doc.data())).includes("Synthetic draft allergy"));
  });

  async function submissionFixture() {
    const api = request(createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(accounts),
      notificationRepository: new InMemoryNotificationRepository(),
      clientIntakeService: new ClientIntakeService(new FirestoreClientIntakeRepository(db)),
    }));
    await new FirestorePrivacyAcceptanceStore(db).recordForClient("client", {
      age: 21, privacy_policy_accepted: true, privacy_policy_version: privacyPolicyVersion,
    });
    await db.doc("customer_purchases/client/purchases/intake-membership").set({
      purchased_at: Timestamp.fromMillis(now - 60_000),
      expires_at: Timestamp.fromMillis(now + 86_400_000),
    });
    const owner = await intakeTestToken(auth, "client");
    const draft = {
      expected_client_id: "client", expected_version: 0, expected_draft_revision: 0,
      guardian_consent_confirmed: false,
      answers: {
        full_name: "Test Client", age: "21",
        date_of_birth: `${new Date().getUTCFullYear() - 21}-01-01`,
        contact_email: "client@fitnep.test", height_cm: "175", weight_kg: "70",
        fitness_goals: "Build endurance", medical_history: "None",
        allergies: "Synthetic allergy", dietary_restrictions: "None",
        food_preferences: "Rice",
      },
    };
    const submit = (payload: object) =>
      api.post("/intakes/me/submit").auth(owner, { type: "bearer" }).send(payload);
    return { api, draft, owner, submit };
  }

  it("submits one version per operation, preserves history, and blocks stale review", async () => {
    const { api, draft, owner, submit } = await submissionFixture();
    const dietitian = await intakeTestToken(auth, "dietitian");
    const replacement = await intakeTestToken(auth, "replacement");
    const unrelated = await intakeTestToken(auth, "other-client");
    const legacyInput = { ...draft, expected_version: 1 };
    await api.put("/intakes/me/draft").auth(owner, { type: "bearer" }).send(legacyInput).expect(200);
    const input = { ...legacyInput, expected_draft_revision: 1, request_id: "submit-intake-version-two" };
    await submit({ ...input, answers: { ...input.answers, allergies: "" } }).expect(400);
    await submit({ ...input, answers: { ...input.answers, weight_kg: "0" } }).expect(400);
    await api.post("/intakes/me/submit").auth(unrelated, { type: "bearer" }).send(input).expect(403);

    const [saved, replay] = await Promise.all([submit(input).expect(200), submit(input).expect(200)]);
    assert.equal(saved.body.data.version, 2);
    assert.equal(replay.body.data.version, 2);
    assert.equal(saved.body.data.draft_revision, 0);
    assert.equal((await db.doc("client_intakes/client/private/draft").get()).exists, false);
    assert.equal((await db.collection("workflow_outbox").get()).size, 1);
    const preserved = db.doc("client_intakes/client/versions/1");
    const original = (await preserved.get()).data();
    assert.deepEqual(original?.allergies, ["Private allergy"]);
    const v2 = db.doc("client_intakes/client/versions/2");
    const frozen = (await v2.get()).data();
    assert.equal(frozen?.health_information.BMI, 22.9);
    assert(frozen?.submitted_at instanceof Timestamp);
    await submit({ ...input, answers: { ...input.answers, weight_kg: "71" } }).expect(409);
    await submit({ ...input, request_id: "different-stale-request" }).expect(409);

    const oldVersion = "/clients/client/intake/versions/1";
    await api.get(oldVersion).auth(owner, { type: "bearer" }).expect(200);
    await api.get(oldVersion).auth(unrelated, { type: "bearer" }).expect(403);
    await api.get(oldVersion).auth(dietitian, { type: "bearer" }).expect(403);
    const sharing = new FirestorePrivacyPreferencesRepository(db);
    await sharing.updateSharing("client", { shareNutritionRecords: true });
    const historical = await api.get(oldVersion).auth(dietitian, { type: "bearer" }).expect(200);
    assert.deepEqual(historical.body.data.intake.allergies, ["Private allergy"]);

    const review = (body: object) => api.patch("/dietitian/assigned-clients/client/intake/review")
      .auth(dietitian, { type: "bearer" }).send(body);
    await review({ action: "reviewed" }).expect(400);
    await review({ action: "reviewed", expected_version: 1 }).expect(400);
    await review({ action: "missing_information", expected_version: 2, note: "Private clarification" }).expect(200);
    assert.deepEqual((await v2.get()).data(), frozen);
    const revised = await submit({
      ...input, expected_version: 2, expected_draft_revision: 0, request_id: "submit-intake-version-three",
      answers: { ...input.answers, allergies: "None", weight_kg: "71" },
    }).expect(200);
    assert.equal(revised.body.data.version, 3);
    assert.equal(revised.body.data.latest.status, "submitted");
    assert.equal(revised.body.data.latest.review_note, null);
    assert.deepEqual(revised.body.data.latest.allergies, []);
    assert.deepEqual((await preserved.get()).data(), original);
    assert.deepEqual((await v2.get()).data(), frozen);
    const olderRetry = await submit(input).expect(200);
    assert.equal(olderRetry.body.data.version, 3);
    const events = await db.collection("workflow_outbox").get();
    assert.equal(events.size, 3);
    assert(!JSON.stringify(events.docs.map(doc => doc.data())).includes("Synthetic allergy"));
    await new HostedWorkflowDelivery(db, () => Date.now() + 1000).drain();
    const notices = await db.collection("notifications").get();
    assert.equal(notices.size, 2);
    assert(notices.docs.every(doc => doc.get("recipient_id") === "dietitian"));
    assert(!JSON.stringify(notices.docs.map(doc => doc.data())).includes("Synthetic allergy"));
    await db.doc("client_assignments/client").update({ dietitian_id: "replacement", version: 2 });
    await api.get(oldVersion).auth(dietitian, { type: "bearer" }).expect(403);
    await api.get(oldVersion).auth(replacement, { type: "bearer" }).expect(200);
    await sharing.updateSharing("client", { shareNutritionRecords: false });
    await api.get(oldVersion).auth(replacement, { type: "bearer" }).expect(403);
  });

  it("sends one intake notice when a client submits before assignment", async () => {
    const { draft, submit } = await submissionFixture();
    const assignment = db.doc("client_assignments/client");
    const savedAssignment = (await assignment.get()).data()!;
    await assignment.delete();
    await db.doc("client_intakes/client").delete();
    const first = await submit({ ...draft, request_id: "submit-before-assignment" }).expect(200);
    assert.equal(first.body.data.version, 1);
    const submitted = await db.collection("workflow_outbox").get();
    assert.equal(submitted.size, 1);
    assert.equal(submitted.docs[0]!.get("event_type"), "intake.submitted");
    const worker = new HostedWorkflowDelivery(db, () => Date.now() + 1000);
    await worker.drain();
    assert.equal((await db.collection("notifications").get()).size, 0);

    await submit({
      ...draft, expected_version: 1, request_id: "revise-before-assignment",
      answers: { ...draft.answers, fitness_goals: "Update my training goal" },
    }).expect(200);
    await assignment.set(savedAssignment);
    await enqueue();
    await worker.drain();
    await worker.drain();
    const notices = await db.collection("notifications").get();
    assert.equal(notices.size, 2);
    assert(notices.docs.every(doc => doc.get("recipient_id") === "dietitian"));
    const intake = notices.docs.filter(doc => doc.get("type") === "intake");
    assert.equal(intake.length, 1);
    assert.equal(intake[0]!.get("reference_id"), "client");
    assert(intake[0]!.get("event_key").endsWith(":v2"));
  });
});

async function intakeTestToken(auth: Auth, uid: string): Promise<string> {
  const password = "FitNEP-emulator-test-123!";
  await auth.updateUser(uid, { password });
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: `${uid}@fitnep.test`, password, returnSecureToken: true }),
    },
  );
  assert(response.ok);
  const token = (await response.json() as { idToken: unknown }).idToken;
  assert(typeof token === "string");
  return token;
}
