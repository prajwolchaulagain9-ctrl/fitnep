import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";
import { after, before, beforeEach, describe, it } from "node:test";
import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import request from "supertest";
import { FirestoreAuditWriter } from "../src/audit";
import { FirestoreAccountService } from "../src/account_service";
import { FirebaseAuthVerifier } from "../src/auth";
import { ClientIntakeService, intakeReviewOperationId } from "../src/client_intake_service";
import { createNotificationApp } from "../src/http_app";
import { HostedWorkflowDelivery } from "../src/workflow_delivery";
import { reconcileAccountAuth } from "../src/account_auth_recovery";
import { PlanAuditContract, planEvents } from "../src/plan_audit_contract";
import { FirestorePrivacyAcceptanceStore, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { FirestorePrivacyPreferencesRepository } from "../src/firestore_privacy_preferences_repository";
import { FirestorePrivateRecordsStore } from "../src/firestore_private_records_store";
import { FirestoreClientIntakeRepository } from "../src/firestore_client_intake_repository";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
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
    await save({ ...input, answers: { ...input.answers, weight_kg: "0" } }).expect(400);
    await save(input).expect(400);
    const draft = db.doc("client_intakes/client/private/draft");
    assert.equal((await draft.get()).exists, false);

    const acceptance = db.doc("privacy_acceptances/client");
    const before = (await acceptance.get()).get("accepted_at") as Timestamp;
    const confirmed = { ...input, guardian_consent_confirmed: true };
    const saved = await save(confirmed).expect(200);
    assert.equal(saved.body.data.membership_active, false);
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
      accounts,
      authVerifier: new FirebaseAuthVerifier(accounts),
      notificationRepository: new InMemoryNotificationRepository(),
      clientIntakeService: new ClientIntakeService(new FirestoreClientIntakeRepository(db)),
      privateRecordsStore: new FirestorePrivateRecordsStore(db, new FirestorePrivacyPreferencesRepository(db)),
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
    const index = (token: string) => api.get("/clients/client/intake/versions").auth(token, { type: "bearer" });
    const legacyList = await index(owner).expect(200);
    assert.deepEqual(legacyList.body.data, {
      client_id: "client", versions: [{ version: 1, submitted_at: null }], next_before: null,
    });
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
    assert.equal(frozen?.health_information.date_of_birth, draft.answers.date_of_birth);
    const displayed = await api.get("/clients/client/intake/versions/2").auth(owner, { type: "bearer" }).expect(200);
    const labels = displayed.body.data.intake.sections.flatMap((section: { fields: { label: string }[] }) =>
      section.fields.map(field => field.label.toLowerCase()));
    assert(!labels.includes("date of birth"));
    assert(!labels.includes("contact email"));
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
    await review({ action: "reviewed", expected_version: 1 }).expect(409);
    const changes = { action: "missing_information", expected_version: 2,
      expected_review_revision: 0, note: "Private clarification" };
    const reviewed = await review(changes).expect(200);
    assert.equal(reviewed.body.data.intake.review_revision, 1);
    const snapshot = await api.get("/clients/client/intake/versions/2").auth(owner, { type: "bearer" }).expect(200);
    assert.equal(snapshot.body.data.intake.status, "submitted");
    assert.equal(snapshot.body.data.intake.review_note, null);
    assert.equal((await review(changes).expect(200)).body.data.intake.review_revision, 1);
    await review({ action: "reviewed", expected_version: 2, expected_review_revision: 0 }).expect(409);
    assert.equal((await db.collection("intake_review_history").get()).size, 1);
    assert.deepEqual((await v2.get()).data(), frozen);
    const revised = await submit({
      ...input, expected_version: 2, expected_draft_revision: 0, request_id: "submit-intake-version-three",
      answers: { ...input.answers, allergies: "None", weight_kg: "71" },
    }).expect(200);
    assert.equal(revised.body.data.version, 3);
    assert.equal(revised.body.data.latest.status, "submitted");
    assert.equal(revised.body.data.latest.review_note, null);
    assert.equal(revised.body.data.latest.review_revision, 0);
    const versions = await index(dietitian).expect("Cache-Control", "no-store").expect(200);
    assert.deepEqual(versions.body.data.versions.map((row: { version: number }) => row.version), [3, 2, 1]);
    assert(!JSON.stringify(versions.body).includes("Synthetic allergy"));
    const olderVersions = await index(owner).query({ before: 3 }).expect(200);
    assert.deepEqual(olderVersions.body.data.versions.map((row: { version: number }) => row.version), [2, 1]);
    await index(owner).query({ before: "invalid" }).expect(400);
    await index(unrelated).expect(403);
    await review({ action: "reviewed", expected_version: 2, expected_review_revision: 1 }).expect(409);
    assert.deepEqual(revised.body.data.latest.allergies, []);
    const weightHistory = (token: string) =>
      api.get("/clients/client/weight-history").auth(token, { type: "bearer" });
    const history = await weightHistory(owner).expect(200);
    assert.deepEqual(history.body.data.records.map((row: { details: { weight_kg: number } }) => row.details.weight_kg), [71, 70]);
    await weightHistory(unrelated).expect(403);
    await weightHistory(dietitian).expect(200);
    await sharing.updateSharing("client", { shareNutritionRecords: false });
    await weightHistory(dietitian).expect(403);
    await sharing.updateSharing("client", { shareNutritionRecords: true });
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
    await index(dietitian).expect(403);
    await api.get(oldVersion).auth(replacement, { type: "bearer" }).expect(200);
    await sharing.updateSharing("client", { shareNutritionRecords: false });
    await api.get(oldVersion).auth(replacement, { type: "bearer" }).expect(403);
    await index(replacement).expect(403);
    await api.get(oldVersion).auth(owner, { type: "bearer" }).expect(200);
  });

  it("keeps basic profile details out of new health drafts and versions", async () => {
    const { api, draft, owner, submit } = await submissionFixture();
    await db.doc("client_intakes/client").delete();
    await db.doc("customer_purchases/client/purchases/intake-membership").delete();
    const patch = (details: object) => api.patch("/profile/me").auth(owner, { type: "bearer" })
      .send({ expected_client_id: "client", ...details });
    const { full_name, age, date_of_birth, contact_email, ...health } = draft.answers;
    const healthDraft = { ...draft, answers: health };
    const save = (input: object) => api.put("/intakes/me/draft").auth(owner, { type: "bearer" }).send(input);
    await save(healthDraft).expect(400);
    const savedPurchase = db.doc("customer_purchases/client/purchases/malformed");
    await savedPurchase.set({ purchased_at: Timestamp.now() });

    await save({ ...draft, answers: { ...draft.answers, contact_phone: "+9779800000000" } }).expect(200);
    const oldDetails = await api.get("/profile/me").auth(owner, { type: "bearer" }).expect(200);
    assert.equal(oldDetails.body.data.account.date_of_birth, date_of_birth);
    assert.equal(oldDetails.body.data.account.contact_phone, "+9779800000000");
    const minorBirth = `${new Date().getUTCFullYear() - 17}-01-01`;
    await patch({ date_of_birth: minorBirth }).expect(400);
    await patch({ expected_client_id: "other-client", date_of_birth: minorBirth,
      guardian_consent_confirmed: true }).expect(403);
    const updated = await patch({ date_of_birth: minorBirth, guardian_consent_confirmed: true }).expect(200);
    assert.equal(updated.body.data.account.full_name, oldDetails.body.data.account.full_name);
    assert.equal(updated.body.data.account.contact_phone, "+9779800000000");

    const saved = await save({ ...healthDraft, expected_draft_revision: 1 }).expect(200);
    assert.equal(saved.body.data.profile_ready, true);
    assert.equal(saved.body.data.membership_active, false);
    assert.deepEqual(saved.body.data.answers, health);
    const profile = await api.get("/profile/me").auth(owner, { type: "bearer" }).expect(200);
    assert.equal(profile.body.data.account.contact_phone, "+9779800000000");
    assert.equal(profile.body.data.account.contact_email, contact_email);
    assert.equal(profile.body.data.account.date_of_birth, minorBirth);
    const submitted = await submit({
      ...healthDraft, expected_draft_revision: 2, request_id: "submit-health-with-separate-profile",
    }).expect(200);
    assert.equal(submitted.body.data.version, 1);
    assert.deepEqual(submitted.body.data.answers, health);
    const record = (await db.doc("client_intakes/client/versions/1").get()).data()!;
    assert.equal(record.health_information.BMI, 22.9);
    assert.equal(record.health_information.date_of_birth, undefined);
    assert.equal(record.responses.contact_email, undefined);
    assert.equal(record.responses.full_name, undefined);
  });

  it("revokes intake history and review when consent or live account authority changes", async () => {
    const { api, draft, owner, submit } = await submissionFixture();
    const dietitian = await intakeTestToken(auth, "dietitian");
    const sharing = new FirestorePrivacyPreferencesRepository(db);
    await sharing.updateSharing("client", { shareNutritionRecords: true });
    await submit({ ...draft, expected_version: 1, request_id: "submit-for-access-recheck" }).expect(200);
    const ownerGet = (path: string) => api.get(path).auth(owner, { type: "bearer" });
    const teamGet = (path: string) => api.get(path).auth(dietitian, { type: "bearer" });
    const current = "/dietitian/assigned-clients/client/intake";
    const history = "/clients/client/intake/versions/1";
    await teamGet(current).expect(200);
    await teamGet(history).expect(200);

    await sharing.updateSharing("client", { shareNutritionRecords: false });
    await teamGet(current).expect(403);
    await teamGet(history).expect(403);
    await api.patch(current + "/review").auth(dietitian, { type: "bearer" })
      .send({ action: "reviewed", expected_version: 2, expected_review_revision: 0 }).expect(403);
    await ownerGet("/intakes/me").expect(200);
    await ownerGet(history).expect(200);
    const consentRef = db.doc("privacy_acceptances/client");
    const acceptance = (await consentRef.get()).data()!;
    await consentRef.delete();
    await ownerGet("/intakes/me").expect(403);
    await ownerGet("/intakes/me/draft").expect(403);
    await ownerGet(history).expect(403);
    await consentRef.set(acceptance);
    await sharing.updateSharing("client", { shareNutritionRecords: true });
    await teamGet(current).expect(200);

    await accounts.change(actor, "dietitian", { role: "staff" });
    await teamGet(current).expect(403);
    await teamGet(history).expect(403);
    await accounts.change(actor, "dietitian", { role: "dietitian" });
    await teamGet(current).expect(403);
    assert.deepEqual((await teamGet("/clients/assigned").expect(200)).body.data.clients, []);

    await accounts.change(actor, "client", { account_status: "inactive" });
    await ownerGet("/intakes/me").expect(403);
    await accounts.change(actor, "client", { account_status: "active" });
    const freshOwner = await intakeTestToken(auth, "client");
    await api.get("/intakes/me").auth(freshOwner, { type: "bearer" }).expect(200);
    await teamGet(current).expect(403);
    assert.equal((await db.collection("intake_review_history").get()).size, 0);
  });

  it("delivers only the current intake request from the assigned dietitian", async () => {
    const { api } = await submissionFixture();
    const dietitian = await intakeTestToken(auth, "dietitian");
    await new FirestorePrivacyPreferencesRepository(db).updateSharing("client", {
      shareNutritionRecords: true,
    });
    const review = (revision: number, action: string, note?: string) =>
      api.patch("/dietitian/assigned-clients/client/intake/review")
        .auth(dietitian, { type: "bearer" })
        .send({ action, expected_version: 1, expected_review_revision: revision, note })
        .expect(200);
    const worker = new HostedWorkflowDelivery(db, () => Date.now() + 1000);

    await review(0, "missing_information", "Private first request");
    const current = await review(1, "clarification_requested", "Private replacement request");
    assert.equal(current.body.data.intake.review_revision, 2);
    const queued = await db.collection("workflow_outbox").get();
    assert.equal(queued.size, 2);
    assert.equal(await worker.drain(), 2);
    const notifications = await db.collection("notifications").get();
    assert.equal(notifications.size, 1);
    assert.equal(notifications.docs[0]!.get("recipient_id"), "client");
    assert.equal(notifications.docs[0]!.get("reference_id"), "client");
    assert.equal(notifications.docs[0]!.get("title"), "Intake information requested");
    assert(!JSON.stringify(notifications.docs[0]!.data()).includes("Private"));
    const eventId = notifications.docs[0]!.get("event_key").split(":")[1];
    const delivered = (await db.doc(`workflow_outbox/${eventId}`).get()).data()!;
    assert.equal(delivered.operation_id, intakeReviewOperationId("client", 1, 2));
    const superseded = queued.docs.find(doc => doc.id !== eventId)!;
    assert.equal((await db.doc(`outbox_handler_receipts/${superseded.id}`).get()).get("result"), "superseded");

    await review(2, "missing_information", "Private closed request");
    await review(3, "reviewed");
    assert.equal(await worker.drain(), 1);
    assert.equal((await db.collection("notifications").get()).size, 1);

    await review(4, "clarification_requested", "Private old assignee request");
    await db.doc("client_assignments/client").update({ dietitian_id: "replacement", version: 2 });
    assert.equal(await worker.drain(), 1);
    assert.equal((await db.collection("notifications").get()).size, 1);
    assert.equal((await db.collection("outbox_handler_receipts").where("result", "==", "superseded").get()).size, 3);
  });

  it("filters and pages the current dietitian's directory, then reflects review and reassignment", async () => {
    const api = request(createNotificationApp({
      accounts,
      authVerifier: new FirebaseAuthVerifier(accounts),
      notificationRepository: new InMemoryNotificationRepository(),
      privateRecordsStore: new FirestorePrivateRecordsStore(db, new FirestorePrivacyPreferencesRepository(db)),
      clientIntakeService: new ClientIntakeService(new FirestoreClientIntakeRepository(db)),
    }));
    const [dietitian, replacement, admin, client] = await Promise.all([
      intakeTestToken(auth, "dietitian"), intakeTestToken(auth, "replacement"),
      intakeTestToken(auth, "admin"), intakeTestToken(auth, "client"),
    ]);
    const list = (token: string) => api.get("/clients/assigned").auth(token, { type: "bearer" });
    const assign = (clientId: string, dietitianId: string) => api.put(`/admin/clients/${clientId}/assignment`)
      .auth(admin, { type: "bearer" }).send({ dietitian_id: dietitianId, staff_ids: [] });
    await list(replacement).expect(200, { data: { clients: [], next_cursor: null } });
    await list(client).expect(403);
    await list(dietitian).query({ dietitian_id: "replacement" }).expect(400);
    await list(dietitian).query({ plan_status: "invalid" }).expect(400);

    const time = Timestamp.fromMillis(now - 10_000);
    const activity = Timestamp.fromMillis(now + 20_000);
    const batch = db.batch();
    batch.update(db.doc("users/client"), { full_name: "Hari Sharma", last_activity_at: activity });
    batch.update(db.doc("users/other-client"), { full_name: "Asha Sharma" });
    batch.set(db.doc("client_intakes/other-client"), {
      review_action: "missing_information", review_updated_at: time, review_note: "Private legacy note",
    });
    for (const uid of ["client", "other-client"]) {
      batch.set(db.doc(`customer_purchases/${uid}/purchases/active`), {
        purchased_at: time, expires_at: Timestamp.fromMillis(now + 86_400_000),
      });
    }
    for (let i = 0; i < 25; i++) {
      const uid = `aa-${String(i).padStart(2, "0")}`;
      batch.set(db.doc(`users/${uid}`), {
        role: "client", account_status: "active", full_name: "Other Name", created_at: time, updated_at: time,
      });
      batch.set(db.doc(`client_assignments/${uid}`), { active: true, dietitian_id: "dietitian" });
    }
    batch.set(db.doc("diet_plans/legacy"), { client_id: "client", created_at: time, description: "Private plan" });
    batch.set(db.doc("diet_plans/latest"), { client_id: "client", status: "published", updated_at: Timestamp.fromMillis(now) });
    await batch.commit();
    const acceptance = new FirestorePrivacyAcceptanceStore(db);
    const sharing = new FirestorePrivacyPreferencesRepository(db);
    for (const uid of ["client", "other-client"]) {
      await acceptance.recordForClient(uid, { age: 21, privacy_policy_accepted: true, privacy_policy_version: privacyPolicyVersion });
      await sharing.updateSharing(uid, { shareNutritionRecords: true });
    }
    await assign("other-client", "dietitian").expect(200);

    const page = await list(dietitian).query({ search: "  shArMa ", limit: 1 })
      .expect("Cache-Control", "no-store").expect(200);
    assert.deepEqual(page.body.data, {
      clients: [{
        id: "client", full_name: "Hari Sharma", email: "client@fitnep.test",
        package_status: "active", plan_status: "published", intake_status: "submitted",
        last_activity_at: activity.toDate().toISOString(),
      }],
      next_cursor: "client",
    });
    const second = await list(dietitian).query({ search: "sharma", limit: 1, after: "client" }).expect(200);
    assert.deepEqual(second.body.data.clients.map((row: { id: string }) => row.id), ["other-client"]);
    assert.equal(second.body.data.clients[0].plan_status, "no_plan");
    assert.equal(second.body.data.clients[0].intake_status, "information_requested");
    assert(!JSON.stringify(second.body).includes("Private legacy note"));
    assert.equal(second.body.data.next_cursor, null);
    const noPlan = await list(dietitian).query({ search: "sharma", plan_status: "no_plan", limit: 1 }).expect(200);
    assert.deepEqual(noPlan.body.data, second.body.data);
    await db.doc("diet_plans/latest").delete();
    const legacy = await list(dietitian).query({ search: "Hari" }).expect(200);
    assert.equal(legacy.body.data.clients[0].plan_status, "unavailable");
    await db.doc("diet_plans/latest").set({
      client_id: "client", status: "published", updated_at: Timestamp.fromMillis(time.toMillis() + 1),
    });

    await db.doc("users/client").update({ last_activity_at: time });
    await db.doc("client_assignments/client").update({ assigned_at: time.toDate().toISOString() });
    await api.patch("/dietitian/assigned-clients/client/intake/review")
      .auth(dietitian, { type: "bearer" }).send({ action: "reviewed", expected_version: 1 }).expect(200);
    const reviewed = await list(dietitian).query({ plan_status: "published" }).expect(200);
    assert.equal(reviewed.body.data.clients[0].intake_status, "reviewed");
    const reviewTime: Timestamp = (await db.doc("client_intakes/client").get()).get("review_updated_at");
    assert.equal(reviewed.body.data.clients[0].last_activity_at, reviewTime.toDate().toISOString());
    assert(!JSON.stringify(reviewed.body).includes("Private"));

    await assign("client", "replacement").expect(200);
    assert.deepEqual((await list(dietitian).query({ search: "Hari" }).expect(200)).body.data.clients, []);
    assert.equal((await list(replacement).expect(200)).body.data.clients[0].id, "client");
    await sharing.updateSharing("client", { shareNutritionRecords: false });
    const withheld = (await list(replacement).expect(200)).body.data.clients[0];
    assert.equal(withheld.plan_status, "unavailable");
    assert.equal(withheld.intake_status, null);
    assert.deepEqual((await list(replacement).query({ plan_status: "published" }).expect(200)).body.data.clients, []);
    const trail = await db.collection("audit_events").where("action", "==", "health.read").get();
    assert(trail.docs.some(doc => doc.get("target_id") === "client/diet-plans" && doc.get("record_ids")?.includes("latest")));
    assert(!JSON.stringify(trail.docs.map(doc => doc.data())).includes("Private"));

    // Exercise the plan producer used by the app and tolerate one malformed
    // purchase without dropping the client from the directory.
    await db.doc("customer_purchases/other-client/purchases/active").update({ expires_at: "invalid" });
    const newPlan = await api.post("/clients/other-client/diet-plans").auth(dietitian, { type: "bearer" })
      .send({ title: "Training plan", description: "Synthetic plan details" }).expect(201);
    const planId = newPlan.body.data.plan.id;
    const expectPlanNotice = async (version: number) => {
      await new HostedWorkflowDelivery(db, () => Date.now() + 1000).drain();
      const query = db.collection("notifications").where("event_key", "==", `plan:${planId}:published:v${version}`);
      for (let attempt = 0; attempt < 30; attempt++) {
        const notices = await query.get();
        if (!notices.empty) {
          assert.equal(notices.size, 1);
          assert.equal(notices.docs[0]!.get("recipient_id"), "other-client");
          return;
        }
        await delay(200);
      }
      assert.fail(`Published plan version ${version} did not notify the client.`);
    };
    await expectPlanNotice(1);
    const otherPlan = await api.get(`/diet-plans/${planId}`).auth(await intakeTestToken(auth, "other-client"), { type: "bearer" }).expect(200);
    assert.equal(otherPlan.body.data.diet_plan.title, "Training plan");
    const newlyPublished = await list(dietitian).query({ search: "Asha", plan_status: "published" }).expect(200);
    assert.equal(newlyPublished.body.data.clients[0].id, "other-client");
    assert.equal(newlyPublished.body.data.clients[0].package_status, "unavailable");
    assert.equal(newlyPublished.body.data.clients[0].plan_status, "published");
    await db.doc("customer_purchases/other-client/purchases/active").update({
      expires_at: Timestamp.fromMillis(now + 86_400_000),
    });
    await db.doc("package_memberships/malformed").set({
      client_id: "other-client", status: "active", created_at: time.toDate().toISOString(),
      package: { duration_days: 30 },
    });
    await api.patch(`/clients/other-client/diet-plans/${planId}`).auth(dietitian, { type: "bearer" })
      .send({ title: "Updated training plan", description: "Synthetic plan details", draft: true, version: 1 }).expect(200);
    const supportedDraft = await list(dietitian).query({ search: "Asha", plan_status: "draft" }).expect(200);
    assert.equal(supportedDraft.body.data.clients[0].plan_status, "draft");
    assert.equal(supportedDraft.body.data.clients[0].package_status, "unavailable");
    const planPath = `/clients/other-client/diet-plans/${planId}`;
    const adminToken = await intakeTestToken(auth, "admin");
    const clientToken = await intakeTestToken(auth, "other-client");
    const act = (token: string, action: string, version: number, reason?: string) =>
      api.patch(planPath).auth(token, { type: "bearer" }).send({ action, version, ...(reason ? { reason } : {}) });
    await act(dietitian, "submit", 2).expect(200);
    await act(adminToken, "approve", 2).expect(403);
    await db.doc("client_assignments/other-client").update({
      team_member_ids: ["admin"], team_member_role_revisions: { admin: 0 },
    });
    await act(adminToken, "return", 2, "Add the client's requested foods.").expect(200);
    const beforePublish = await api.get(`/diet-plans/${planId}`).auth(clientToken, { type: "bearer" }).expect(200);
    assert.equal(beforePublish.body.data.diet_plan.title, "Training plan");
    await api.patch(planPath).auth(dietitian, { type: "bearer" })
      .send({ title: "Revised training plan", description: "New synthetic details", draft: true, version: 2 }).expect(200);
    await act(dietitian, "submit", 3).expect(200);
    await act(adminToken, "approve", 2).expect(400);
    await act(adminToken, "approve", 3).expect(200);
    await act(dietitian, "publish", 3).expect(200);
    await expectPlanNotice(3);
    const published = await api.get(`/diet-plans/${planId}`).auth(clientToken, { type: "bearer" }).expect(200);
    assert.equal(published.body.data.diet_plan.title, "Revised training plan");
    assert.equal((await db.doc(`diet_plans/${planId}/versions/2`).get()).get("status"), "returned");
    const planTrail = await db.collection("audit_events").where("target_id", "==", planId).get();
    const planActions = planTrail.docs.filter(doc => String(doc.get("action")).startsWith("plan."));
    assert.deepEqual(new Set(planActions.map(doc => doc.get("action"))), new Set([
      "plan.created", "plan.submitted", "plan.returned", "plan.approved", "plan.published", "plan.revised",
    ]));
    assert(planActions.every(doc => doc.get("version") > 0 && doc.get("actor_id") && doc.get("occurred_at")));
  });

  it("accepts unpaid intake submissions and sends one notice after assignment", async () => {
    const { draft, submit } = await submissionFixture();
    const clientNotices = async () => {
      const snapshot = await db.collection("notifications")
        .where("reference_id", "==", draft.expected_client_id).get();
      return snapshot.docs.filter(doc => ["intake", "assignment"].includes(doc.get("type")));
    };
    const assignment = db.doc("client_assignments/client");
    const savedAssignment = (await assignment.get()).data()!;
    await assignment.delete();
    await db.doc("client_intakes/client").delete();
    await db.doc("customer_purchases/client/purchases/intake-membership").delete();
    const first = await submit({ ...draft, request_id: "submit-before-assignment" }).expect(200);
    assert.equal(first.body.data.version, 1);
    assert.equal(first.body.data.membership_active, false);
    const submitted = await db.collection("workflow_outbox").get();
    assert.equal(submitted.size, 1);
    assert.equal(submitted.docs[0]!.get("event_type"), "intake.submitted");
    const worker = new HostedWorkflowDelivery(db, () => Date.now() + 1000);
    await worker.drain();
    // An asynchronous plan trigger can finish after the preceding test resets.
    await new FirestoreNotificationRepository(db).createIfAbsent({
      id: "unrelated-plan",
      recipientId: "other-client",
      type: "diet_plan",
      referenceId: draft.expected_client_id,
      eventKey: "unrelated-plan-notice",
      title: "Diet plan assigned",
      message: "Your diet plan is available.",
      createdAt: new Date().toISOString(),
    });
    assert.equal((await clientNotices()).length, 0);

    await submit({
      ...draft, expected_version: 1, request_id: "revise-before-assignment",
      answers: { ...draft.answers, fitness_goals: "Update my training goal" },
    }).expect(200);
    await assignment.set(savedAssignment);
    await enqueue();
    await worker.drain();
    await worker.drain();
    const notices = await clientNotices();
    assert.equal(notices.length, 2);
    assert(notices.every(doc => doc.get("recipient_id") === "dietitian"));
    const intake = notices.filter(doc => doc.get("type") === "intake");
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
