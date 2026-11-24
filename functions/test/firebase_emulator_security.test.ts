import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import request from "supertest";

import type { CallableRequest } from "firebase-functions/v2/https";
import { FirestoreAuditWriter } from "../src/audit";
import { registrationPrivacy } from "../src/registration_privacy";
import { FirebaseAuthVerifier } from "../src/auth";
import { FirebaseStaffAccountRepository } from "../src/firebase_staff_account_repository";
import { UserRole } from "../src/domain";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
import { FirestorePrivacyAcceptanceStore, PrivacyAcceptanceError, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { FirestorePrivacyPreferencesRepository } from "../src/firestore_privacy_preferences_repository";
import { FirestorePrivateRecordsStore } from "../src/firestore_private_records_store";
import { FirestoreClientAssignmentRepository } from "../src/firestore_client_assignment_repository";
import { FirestorePackageRepository } from "../src/firestore_package_repository";
import { FirestorePackageService } from "../src/package_membership_service";
import { FirestorePlatformSessionService } from "../src/platform_sessions";
import {
  addCalendarMonths,
  FirestorePurchaseRepository,
} from "../src/firestore_purchase_repository";
import { createNotificationApp } from "../src/http_app";
import { NotificationWorkflowService } from "../src/notification_service";
import {
  ClientAssignmentService,
  FirebaseClientDirectory,
} from "../src/client_assignment_service";

const projectId = "demo-fitnep";
const authEmulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreEmulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const emulatorDescribe =
  authEmulatorHost === undefined || firestoreEmulatorHost === undefined
    ? describe.skip
    : describe;

emulatorDescribe("Firebase Auth and Firestore recipient isolation", () => {
  let firebaseApp: App;
  let auth: Auth;
  let firestore: Firestore;
  let repository: FirestoreNotificationRepository;
  let workflows: NotificationWorkflowService;
  let packageRepository: FirestorePackageRepository;
  let purchaseRepository: FirestorePurchaseRepository;
  let api: ReturnType<typeof createNotificationApp>;

  before(() => {
    firebaseApp = initializeApp({ projectId });
    auth = getAuth(firebaseApp);
    firestore = getFirestore(firebaseApp);
    repository = new FirestoreNotificationRepository(firestore);
    packageRepository = new FirestorePackageRepository(firestore);
    purchaseRepository = new FirestorePurchaseRepository(firestore);
    workflows = new NotificationWorkflowService(repository);
    const privacyPreferencesRepository = new FirestorePrivacyPreferencesRepository(firestore);
    api = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      staffAccountRepository: new FirebaseStaffAccountRepository(auth, firestore),
      packageRepository,
      purchaseRepository,
      packageService: new FirestorePackageService(firestore),
      privacyPreferencesRepository,
      privateRecordsStore: new FirestorePrivateRecordsStore(firestore, privacyPreferencesRepository),
    });
  });

  beforeEach(async () => {
    await Promise.all([clearAuth(), clearFirestore()]);
    await Promise.all([
      createAccount(auth, "client-a", "client-a@fitnep.test", "client"),
      createAccount(auth, "client-b", "client-b@fitnep.test", "client"),
      createAccount(
        auth,
        "dietitian-1",
        "dietitian@fitnep.test",
        "dietitian",
      ),
      createAccount(
        auth,
        "admin-1",
        "admin@fitnep.test",
        "admin",
        "FitNep CEO",
      ),
    ]);
  });

  after(async () => {
    await deleteApp(firebaseApp);
  });

  it("lets only admins list paginated staff accounts and preserves inactive status", async () => {
    await createAccount(auth, "staff-1", "staff@fitnep.test", "staff", "Demo Staff");
    await auth.createUser({
      uid: "unknown-role",
      email: "unassigned@fitnep.test",
      displayName: "Unassigned account",
    });

    const directory = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      // Force mixed-role pagination with a small fixture.
      staffAccountRepository: new FirebaseStaffAccountRepository(auth, firestore, 2),
    });
    const path = "/admin/staff-accounts";
    await request(directory).get(path).expect(401);
    const [clientToken, dietitianToken, staffToken] = await Promise.all([
      signIn("client-a@fitnep.test"),
      signIn("dietitian@fitnep.test"),
      signIn("staff@fitnep.test"),
    ]);
    for (const token of [clientToken, dietitianToken, staffToken]) {
      await request(directory).get(path).query({ role: "admin" }).set(bearer(token)).expect(403);
    }
    await request(directory).get("/notifications").set(bearer(staffToken)).expect(403);
    await request(directory).patch("/notifications/read-all").set(bearer(staffToken)).expect(403);
    await request(directory).get("/packages").set(bearer(staffToken)).expect(403);

    await auth.updateUser("staff-1", { disabled: true });
    const admin = bearer(await signIn("admin@fitnep.test"));
    await request(directory).get(`${path}?cursor=a&cursor=b`).set(admin).expect(400);
    const accounts: Array<{ uid: string }> = [];
    const seenCursors = new Set<string>();
    let cursor: string | null = null;
    do {
      const response = await request(directory)
        .get(path).query(cursor === null ? {} : { cursor }).set(admin).expect(200);
      accounts.push(...response.body.data.accounts);
      cursor = response.body.data.next_cursor as string | null;
      if (cursor !== null) {
        assert(!seenCursors.has(cursor));
        seenCursors.add(cursor);
      }
    } while (cursor !== null);

    assert(seenCursors.size > 0);
    assert.deepEqual(accounts.map((account) => account.uid).sort(), [
      "admin-1", "dietitian-1", "staff-1",
    ]);
    assert.deepEqual(accounts.find((account) => account.uid === "staff-1"), {
      uid: "staff-1",
      name: "Demo Staff",
      email: "staff@fitnep.test",
      role: "staff",
      is_active: false,
    });
  });

  it("creates staff with an audited temporary password and requires a different password before granting access", async () => {
    const admin = bearer(await signIn("admin@fitnep.test"));
    const client = bearer(await signIn("client-a@fitnep.test"));
    const directory = "/admin/staff-accounts";
    const passwordPath = "/auth/staff/change-temporary-password";
    const input = {
      request_id: "create-new-manager",
      name: "New Manager",
      email: "manager@fitnep.test",
      role: "admin",
      temporary_password: "TemporaryExample!12",
    };
    await request(api).post(directory).set(client).send(input).expect(403);
    await request(api).post(directory).set(admin).send({ ...input, role: "client" }).expect(400);
    const created = await request(api).post(directory).set(admin).send(input).expect(201);
    const account = created.body.data.account;
    assert.deepEqual(Object.keys(account).sort(), ["email", "is_active", "name", "role", "uid"]);
    const retry = await request(api).post(directory).set(admin).send(input).expect(201);
    assert.deepEqual(retry.body.data.account, account);
    await request(api).post(directory).set(admin)
      .send({ ...input, name: "Different Manager" }).expect(409);
    await request(api).post(directory).set(admin)
      .send({ ...input, request_id: "duplicate-email" }).expect(409);
    assert.equal((await firestore.collection("staff_account_history").get()).size, 1);
    assert.equal((await firestore.collection("staff_password_setup").get()).size, 1);
    assert.equal((await auth.getUser(account.uid)).customClaims?.mustChangePassword, true);

    const temporaryToken = await signIn(input.email, input.temporary_password);
    const temporarySession = bearer(temporaryToken);
    await request(api).get(directory).set(temporarySession).expect(403);
    await request(api).post(directory).set(temporarySession).send(input).expect(403);
    await request(api).post(passwordPath).set(temporarySession)
      .send({ new_password: input.temporary_password }).expect(400);
    const newPassword = "PermanentExample!34";
    const pendingActor = await new FirebaseAuthVerifier().verifyIdToken(temporaryToken);
    const claims = (await auth.getUser(account.uid)).customClaims;
    await auth.setCustomUserClaims(account.uid, { ...claims, staffRoleVersion: "changed-during-setup" });
    const staff = new FirebaseStaffAccountRepository(auth, firestore);
    await assert.rejects(staff.changeTemporaryPassword(pendingActor, newPassword), { status: 403 });
    const refreshedTemporarySession = bearer(await signIn(input.email, input.temporary_password));
    const hosted = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(auth),
      notificationRepository: repository,
      staffAccountRepository: staff,
      platformSessions: new FirestorePlatformSessionService(firestore, new FirestoreAuditWriter(firestore)),
    });
    await request(hosted).post("/sessions/start").set(refreshedTemporarySession).send({}).expect(403);
    await request(hosted).get(directory).set(refreshedTemporarySession).expect(403);
    await request(hosted).post(passwordPath).set(refreshedTemporarySession)
      .send({ new_password: newPassword }).expect(204);
    await assert.rejects(signIn(input.email, input.temporary_password));
    await request(api).get(directory).set(refreshedTemporarySession).expect(401);
    const newSession = bearer(await signIn(input.email, newPassword));
    const started = await request(hosted).post("/sessions/start").set(newSession).send({}).expect(200);
    await request(hosted).get(directory).set(newSession)
      .set("X-FitNEP-Session", started.body.data.session_id).expect(200);
    await request(api).get(directory).set(newSession).expect(200);
    await request(api).post(passwordPath).set(newSession)
      .send({ new_password: "DifferentPassword!45" }).expect(403);
    assert.equal((await firestore.collection("staff_password_setup").doc(account.uid).get()).exists, false);

    const audit = await firestore.collection("staff_account_history").where("target_uid", "==", account.uid).get();
    assert.equal(audit.size, 1);
    const entry = audit.docs[0]?.data();
    assert.equal(entry?.actor_uid, "admin-1");
    assert.equal(entry?.action, "created");
    assert.equal(entry?.status, "completed");
    assert(!JSON.stringify(entry).includes(input.temporary_password));
  });

  it("audits staff edits, keeps the account UID, and rejects the previous role session", async () => {
    await createAccount(auth, "team-member", "team-member@fitnep.test", "staff");
    await auth.setCustomUserClaims("team-member", { role: "staff", otherClaim: true });
    const admin = bearer(await signIn("admin@fitnep.test"));
    const previousSession = bearer(await signIn("team-member@fitnep.test"));
    const path = "/admin/staff-accounts/team-member";
    const changes = { request_id: "edit-member-role", name: "Dietitian", role: "dietitian" };
    await request(api).patch(path).set(previousSession).send(changes).expect(403);
    await request(api).patch("/admin/staff-accounts/client-a").set(admin).send(changes).expect(404);
    await request(api).patch("/admin/staff-accounts/admin-1").set(admin).send(changes).expect(403);
    const response = await request(api).patch(path).set(admin).send(changes).expect(200);
    assert.deepEqual(response.body.data.account, {
      uid: "team-member",
      name: "Dietitian",
      email: "team-member@fitnep.test",
      role: "dietitian",
      is_active: true,
    });
    await request(api).get("/packages").set(previousSession).expect(401);
    const currentSession = bearer(await signIn("team-member@fitnep.test"));
    await request(api).get("/packages").set(currentSession).expect(200);
    await request(api).patch(path).set(admin).send(changes).expect(200);
    assert.equal((await auth.getUser("team-member")).customClaims?.otherClaim, true);
    const audit = await firestore.collection("staff_account_history").where("target_uid", "==", "team-member").get();
    assert.equal(audit.size, 1);
    const event = audit.docs[0];
    assert(event);
    const entry = event.data();
    assert.equal(entry?.action, "role_changed");
    assert.equal(entry?.before.role, "staff");
    assert.equal(entry?.after.role, "dietitian");

    // Recover an edit whose Auth update finished before its audit was finalized.
    await event.ref.update({ status: "pending" });
    await request(api).patch(path).set(admin).send(changes).expect(200);
    await request(api).get("/packages").set(currentSession).expect(200);
    assert.equal((await event.ref.get()).get("status"), "completed");

    // A later role change can bring the account back to the original role.
    // Retrying the older pending edit must still preserve that newer change.
    await event.ref.update({ status: "pending" });
    await request(api).patch(path).set(admin)
      .send({ request_id: "later-role-change", role: "staff" }).expect(200);
    await request(api).patch(path).set(admin).send(changes).expect(409);
    assert.equal((await auth.getUser("team-member")).customClaims?.role, "staff");
  });

  it("deactivates and reactivates the same staff account, revokes sessions, and keeps its history", async () => {
    const admin = bearer(await signIn("admin@fitnep.test"));
    const directory = "/admin/staff-accounts";
    const historyPath = `${directory}/history`;
    const email = "managed-dietitian@fitnep.test";
    const temporaryPassword = "TemporaryExample!12";
    const created = await request(api).post(directory).set(admin).send({
      request_id: "create-managed-account",
      name: "Managed Account",
      role: "dietitian",
      email,
      temporary_password: temporaryPassword,
    }).expect(201);
    const { uid } = created.body.data.account;
    const pending = bearer(await signIn(email, temporaryPassword));
    const password = "PermanentExample!34";
    await request(api).post("/auth/staff/change-temporary-password").set(pending)
      .send({ new_password: password }).expect(204);
    const oldSession = bearer(await signIn(email, password));
    await request(api).get("/packages").set(oldSession).expect(200);
    await request(api).patch(`${directory}/${uid}`).set(admin)
      .send({ request_id: "rename-managed-account", name: "Managed Dietitian" }).expect(200);

    const statusPath = `${directory}/${uid}/active`;
    const deactivate = { request_id: "disable-managed-account", is_active: false };
    const reactivate = { request_id: "enable-managed-account", is_active: true };
    const noChange = { request_id: "already-active", is_active: true };
    for (const email of ["client-a@fitnep.test", "dietitian@fitnep.test"]) {
      const nonAdmin = bearer(await signIn(email));
      await request(api).patch(statusPath).set(nonAdmin).send(deactivate).expect(403);
      await request(api).get(historyPath).set(nonAdmin).expect(403);
    }
    await request(api).get(historyPath).expect(401);
    await request(api).patch(`${directory}/admin-1/active`).set(admin).send(deactivate).expect(403);
    await request(api).patch(`${directory}/client-a/active`).set(admin).send(deactivate).expect(404);
    await request(api).patch(statusPath).set(admin).send({ ...deactivate, is_active: "false" }).expect(400);

    await request(api).patch(statusPath).set(admin).send(noChange).expect(200);
    const disabled = await request(api).patch(statusPath).set(admin).send(deactivate).expect(200);
    assert.equal(disabled.body.data.account.is_active, false);
    await request(api).get("/packages").set(oldSession).expect(401);
    await assert.rejects(signIn(email, password));
    await request(api).patch(statusPath).set(admin).send(noChange).expect(200);
    assert.equal((await auth.getUser(uid)).disabled, true);
    const restored = await request(api).patch(statusPath).set(admin).send(reactivate).expect(200);
    assert.deepEqual(restored.body.data.account, {
      uid, name: "Managed Dietitian", email, role: "dietitian", is_active: true,
    });
    await request(api).patch(statusPath).set(admin).send(deactivate).expect(200);
    await request(api).get("/packages").set(oldSession).expect(401);
    await request(api).get("/packages").set(bearer(await signIn(email, password))).expect(200);

    const pagedApi = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      staffAccountRepository: new FirebaseStaffAccountRepository(auth, firestore, 2),
    });
    const first = (await request(pagedApi).get(historyPath).set(admin).expect(200)).body.data;
    assert.deepEqual(first.entries.map((entry: { action: string }) => entry.action), [
      "reactivated", "deactivated",
    ]);
    assert.equal(first.entries[1].before.is_active, true);
    assert.equal(first.entries[1].after.is_active, false);
    assert.equal(first.entries[1].actor_uid, "admin-1");
    assert.equal(first.entries[1].actor_name, "FitNep CEO");
    assert.equal(first.entries[1].after.uid, uid);
    assert(!Number.isNaN(Date.parse(first.entries[1].completed_at)));
    const second = (await request(pagedApi).get(historyPath)
      .query({ cursor: first.next_cursor }).set(admin).expect(200)).body.data;
    assert.deepEqual(second.entries.map((entry: { action: string }) => entry.action), [
      "updated", "created",
    ]);
    assert.equal(second.next_cursor, null);
    assert(!JSON.stringify([first, second]).includes(temporaryPassword));
    await request(api).get(historyPath).query({ cursor: "." }).set(admin).expect(400);
  });

  it("finishes an interrupted deactivation before accepting a later reactivation", async (t) => {
    const admin = bearer(await signIn("admin@fitnep.test"));
    const email = "dietitian@fitnep.test";
    const oldSession = bearer(await signIn(email));
    const path = "/admin/staff-accounts/dietitian-1/active";
    const historyPath = "/admin/staff-accounts/history";
    const claimsWrite = t.mock.method(auth, "setCustomUserClaims", async () => {
      throw new Error("Injected failure writing custom claims after disabling the account");
    });
    await request(api).patch(path).set(admin)
      .send({ request_id: "interrupted-disable", is_active: false }).expect(503);
    claimsWrite.mock.restore();
    await assert.rejects(signIn(email));
    await request(api).get("/packages").set(oldSession).expect(401);
    const pending = await request(api).get(historyPath).set(admin).expect(200);
    assert.deepEqual(pending.body.data.entries, []);

    await request(api).patch(path).set(admin)
      .send({ request_id: "later-enable", is_active: true }).expect(200);
    const history = await request(api).get(historyPath).set(admin).expect(200);
    assert.deepEqual(history.body.data.entries.map((entry: { action: string }) => entry.action), [
      "reactivated", "deactivated",
    ]);
    await request(api).get("/packages").set(oldSession).expect(401);
    await request(api).get("/packages").set(bearer(await signIn(email))).expect(200);
  });

  it("binds signup consent and its status to the signed-in Firebase account", async () => {
    let token = await signIn("client-a@fitnep.test");
    const requestFor = (data: Record<string, unknown>) => ({
      auth: { uid: "client-a" },
      rawRequest: { headers: { authorization: `Bearer ${token}` } },
      data,
    } as CallableRequest);
    const call = (data: Record<string, unknown>) => registrationPrivacy.run(requestFor(data));
    const adult = { uid: "client-a", action: "accept", age: 18, privacy_policy_accepted: true,
      privacy_policy_version: privacyPolicyVersion };
    await assert.rejects(call(adult), {
      code: "failed-precondition",
      message: "Verify your email before recording privacy consent.",
    });
    await auth.updateUser("client-a", { emailVerified: true });
    token = await signIn("client-a@fitnep.test");
    const status = { uid: "client-a", action: "status" };
    assert.deepEqual(await call(status), { accepted: false });
    await assert.rejects(call({ ...adult, uid: "client-b" }), { code: "failed-precondition" });
    await assert.rejects(call({ ...adult, age: 17 }), { code: "invalid-argument" });
    assert.deepEqual(await call(adult), { accepted: true });
    assert.deepEqual(await call(status), { accepted: true });
  });

  it("stores the server acceptance date once and requires confirmation for minors", async () => {
    const acceptanceStore = new FirestorePrivacyAcceptanceStore(firestore);
    const reference = firestore.collection("privacy_acceptances").doc("client-a");
    const form = {
      age: 17,
      privacy_policy_version: privacyPolicyVersion,
      privacy_policy_accepted: true,
    };
    await assert.rejects(acceptanceStore.recordForClient("client-a", form), PrivacyAcceptanceError);
    assert.equal((await reference.get()).exists, false);
    const confirmed = { ...form, guardian_consent_confirmed: true };
    await acceptanceStore.recordForClient("client-a", confirmed);
    const stored = await reference.get();
    assert.equal(stored.get("policy_version"), privacyPolicyVersion);
    assert.equal(stored.get("age_at_acceptance"), 17);
    assert(stored.get("accepted_at") instanceof Timestamp);
    assert(stored.get("guardian_consent_confirmed_at") instanceof Timestamp);
    await acceptanceStore.recordForClient("client-a", confirmed);
    assert.deepEqual((await reference.get()).get("accepted_at"), stored.get("accepted_at"));
  });

  it("allows only the owner to record a valid age and consent with a server timestamp", async () => {
    const token = await signIn("client-a@fitnep.test");
    let headers = { ...bearer(token), "Content-Type": "application/json" };
    const database = `projects/${projectId}/databases/(default)`;
    const endpoint = `http://${firestoreEmulatorHost}/v1/${database}/documents`;
    const records = `${endpoint}/privacy_acceptances`;
    const writeConsent = (uid: string, age: number, guardian: boolean) => fetch(`${endpoint}:commit`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        writes: [{
          update: {
            name: `${database}/documents/privacy_acceptances/${uid}`,
            fields: {
              policy_version: { stringValue: privacyPolicyVersion },
              age_at_acceptance: { integerValue: String(age) },
              guardian_consent_confirmed: { booleanValue: guardian },
            },
          },
          updateTransforms: [
            { fieldPath: "accepted_at", setToServerValue: "REQUEST_TIME" },
            ...(guardian ? [{
              fieldPath: "guardian_consent_confirmed_at",
              setToServerValue: "REQUEST_TIME",
            }] : []),
          ],
        }],
      }),
    });

    assert.equal((await writeConsent("client-a", 17, true)).status, 403);
    await auth.updateUser("client-a", { emailVerified: true });
    headers = { ...bearer(await signIn("client-a@fitnep.test")), "Content-Type": "application/json" };
    assert.equal((await fetch(`${records}/client-a`, { headers })).status, 404);
    assert.equal((await fetch(`${records}/client-b`, { headers })).status, 403);
    assert.equal((await writeConsent("client-b", 17, true)).status, 403);
    assert.equal((await writeConsent("client-a", 0, true)).status, 403);
    assert.equal((await writeConsent("client-a", 17, false)).status, 403);
    assert.equal((await writeConsent("client-a", 17, true)).status, 200);
    assert.equal((await fetch(`${records}/client-a`, { headers })).status, 200);
    assert.equal((await writeConsent("client-a", 18, false)).status, 403);
    const consent = await firestore.collection("privacy_acceptances").doc("client-a").get();
    assert.equal(consent.get("age_at_acceptance"), 17);
    assert(consent.get("accepted_at") instanceof Timestamp);
    assert.deepEqual(consent.get("guardian_consent_confirmed_at"), consent.get("accepted_at"));
  });

  it("lets a verified user without a role manage only their own sharing after accepting the policy", async () => {
    await auth.createUser({
      uid: "new-client",
      email: "new-client@fitnep.test",
      password: "Password123!",
      emailVerified: true,
    });
    const token = await signIn("new-client@fitnep.test");
    const url = `http://${firestoreEmulatorHost}/v1/projects/${projectId}/databases/(default)/documents/privacy_preferences/new-client`;
    const readSharing = () => fetch(url, { headers: bearer(token) });
    assert.equal((await readSharing()).status, 403);
    assert.equal(await writeSharing("new-client", token, { share_activity_data: true }), 403);

    await new FirestorePrivacyAcceptanceStore(firestore).recordForClient("new-client", {
      age: 18,
      privacy_policy_version: privacyPolicyVersion,
      privacy_policy_accepted: true,
    });
    assert.equal((await readSharing()).status, 404);
    assert.equal(await writeSharing("client-b", token, { share_activity_data: true }), 403);
    assert.equal(await writeSharing("new-client", token, { share_activity_data: "yes" }), 403);
    assert.equal(await writeSharing("new-client", token, { role: "admin" }), 403);
    assert.equal(await writeSharing("new-client", token, { share_progress_photos: true }), 200);
    assert.equal(await writeSharing("new-client", token, { share_activity_data: true }), 200);
    assert.equal((await readSharing()).status, 200);
    const prefs = await firestore.collection("privacy_preferences").doc("new-client").get();
    assert.equal(prefs.get("share_progress_photos"), true);
    assert.equal(prefs.get("share_activity_data"), true);
  });

  it("withdrawal blocks new records and dietitian reads without deleting existing data", async () => {
    await auth.updateUser("client-a", { emailVerified: true });
    await new FirestorePrivacyAcceptanceStore(firestore).recordForClient("client-a", {
      age: 18,
      privacy_policy_version: privacyPolicyVersion,
      privacy_policy_accepted: true,
    });
    const [clientToken, dietitianToken, adminToken] = await Promise.all([
      signIn("client-a@fitnep.test"), signIn("dietitian@fitnep.test"), signIn("admin@fitnep.test"),
    ]);
    const client = bearer(clientToken);
    const dietitian = bearer(dietitianToken);
    const assignment = firestore.collection("client_assignments").doc("client-a");
    await assignment.set({ active: true, dietitian_id: "dietitian-1" });
    const activity = "/clients/client-a/records/activity-data";
    const progress = "/clients/client-a/records/progress-photos";
    const prefs = "/privacy/preferences";
    const sample = { steps: 1000, active_minutes: 30 };
    const photo = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN84AAAAASUVORK5CYII=", "base64");

    await request(api).post(activity).set(client).send(sample).expect(403);
    await request(api).patch(prefs).set(client).send({ share_progress_photos: true }).expect(200);
    await request(api).post(activity).set(client).send(sample).expect(403);
    const created = await request(api).post(progress).set(client).type("png").send(photo).expect(201);
    const imagePath = `${progress}/${created.body.data.record.id}/photo`;
    await request(api).get(imagePath).set(dietitian).expect(200).expect("Content-Type", "image/png");
    await request(api).get(imagePath).set(bearer(adminToken)).expect(403);
    assert.equal(await writeSharing("client-a", clientToken, { share_activity_data: true }), 200);
    await request(api).post(activity).set(client).send(sample).expect(201);
    await request(api).get(activity).set(dietitian).expect(200);
    await assignment.update({ dietitian_id: "replacement" });
    await request(api).get(activity).set(dietitian).expect(403);
    await assignment.update({ dietitian_id: "dietitian-1" });

    assert.equal(await writeSharing("client-a", clientToken, {
      share_activity_data: false,
      share_progress_photos: false,
    }), 200);
    await request(api).post(activity).set(client).send(sample).expect(403);
    await request(api).post(progress).set(client).type("png").send(photo).expect(403);
    await request(api).get(activity).set(dietitian).expect(403);
    await request(api).get(imagePath).set(dietitian).expect(403);
    await request(api).get(imagePath).set(client).expect(200);
    const own = await request(api).get(activity).set(client).expect(200);
    assert.deepEqual(own.body.data.records.map((record: { details: unknown }) => record.details), [sample]);
  });

  it("persists assignment and reassignment audits without duplicates", async () => {
    await createAccount(
      auth,
      "dietitian-2",
      "dietitian-2@fitnep.test",
      "dietitian",
    );
    const assignmentRepository = new FirestoreClientAssignmentRepository(
      firestore,
      new FirestoreAuditWriter(firestore),
    );
    const assignmentApi = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      clientAssignmentService: new ClientAssignmentService(
        assignmentRepository,
        { getStatus: async () => "active" },
        {
          isActiveDietitian: async uid =>
            uid === "dietitian-1" || uid === "dietitian-2",
        },
        null,
        new FirebaseClientDirectory(auth),
        (() => {
          let hour = 12;
          return () => new Date(`2026-11-24T${hour++}:00:00.000Z`);
        })(),
      ),
    });
    const [adminToken, dietitianAToken, dietitianBToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("dietitian@fitnep.test"),
      signIn("dietitian-2@fitnep.test"),
    ]);
    const path = "/admin/client-assignments/client-a";
    const clientPath = "/dietitian/assigned-clients/client-a";

    await firestore.collection("client_assignments").doc("client-a").set({
      active: true,
      client_id: "client-a",
      dietitian_id: "dietitian-1",
      assigned_at: "2026-11-23T12:00:00.000Z",
      assigned_by_id: "admin-1",
      version: 1,
    });
    assert.equal((await firestore.collection("client_assignment_history")
      .where("client_id", "==", "client-a").get()).empty, true);
    await request(assignmentApi)
      .put("/admin/client-assignments/client-b")
      .set(bearer(adminToken))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);
    await request(assignmentApi).get(clientPath)
      .set(bearer(dietitianAToken)).expect(200);
    await request(assignmentApi).get(clientPath)
      .set(bearer(dietitianBToken)).expect(403);

    await request(assignmentApi).put(path).set(bearer(adminToken))
      .send({ dietitian_id: "dietitian-2" }).expect(200);

    await request(assignmentApi).get(clientPath)
      .set(bearer(dietitianAToken)).expect(403);
    await request(assignmentApi).get(clientPath)
      .set(bearer(dietitianBToken)).expect(200);
    const current = await firestore.collection("client_assignments")
      .doc("client-a").get();
    assert.equal(current.get("dietitian_id"), "dietitian-2");
    assert.equal(current.get("version"), 2);
    const history = await firestore.collection("client_assignment_history")
      .where("client_id", "==", "client-a").get();
    assert.deepEqual(
      history.docs
        .map(document => [document.get("version"), document.get("dietitian_id")])
        .sort((left, right) => Number(left[0]) - Number(right[0])),
      [[1, "dietitian-1"], [2, "dietitian-2"]],
    );
    await request(assignmentApi).put(path).set(bearer(adminToken))
      .send({ dietitian_id: "dietitian-2" }).expect(200);
    const unchangedHistory = await firestore.collection("client_assignment_history")
      .where("client_id", "==", "client-a").get();
    assert.deepEqual(
      unchangedHistory.docs
        .map(document => [document.get("version"), document.get("dietitian_id")])
        .sort((left, right) => Number(left[0]) - Number(right[0])),
      [[1, "dietitian-1"], [2, "dietitian-2"]],
    );
    const assignmentAudits = await firestore.collection("audit_events")
      .where("target_type", "==", "assignment").get();
    assert.equal(assignmentAudits.size, 2);
    const assignmentAudit = assignmentAudits.docs
      .map(document => document.data())
      .find(event => event.action === "client.assigned");
    assert(assignmentAudit);
    assert.equal(assignmentAudit.client_id, "client-b");
    assert.equal(assignmentAudit.dietitian_id, "dietitian-1");
    assert.equal("previous_dietitian_id" in assignmentAudit, false);
    assert.equal(assignmentAudit.actor_id, "admin-1");
    assert.equal(assignmentAudit.actor_name, "FitNep CEO");
    assert.equal(assignmentAudit.target_id, "client-b");
    assert.equal(assignmentAudit.outcome, "succeeded");
    assert.equal(assignmentAudit.version, 1);
    assert(assignmentAudit.occurred_at instanceof Timestamp);
    const reassignmentAudit = assignmentAudits.docs
      .map(document => document.data())
      .find(event => event.action === "client.reassigned");
    assert(reassignmentAudit);
    assert.equal(reassignmentAudit.client_id, "client-a");
    assert.equal(reassignmentAudit.previous_dietitian_id, "dietitian-1");
    assert.equal(reassignmentAudit.dietitian_id, "dietitian-2");
    assert.equal(reassignmentAudit.actor_id, "admin-1");
    assert.equal(reassignmentAudit.actor_name, "FitNep CEO");
    assert.equal(reassignmentAudit.target_id, "client-a");
    assert.equal(reassignmentAudit.outcome, "succeeded");
    assert.equal(reassignmentAudit.version, 2);
    assert(reassignmentAudit.occurred_at instanceof Timestamp);

    const historyUrl = `http://${firestoreEmulatorHost}/v1/projects/${projectId}` +
      "/databases/(default)/documents/client_assignment_history/client-a_v1";
    assert.equal((await fetch(historyUrl, {
      headers: bearer(dietitianAToken),
    })).status, 403);
  });

  it("enforces ownership with real emulator ID tokens and persisted records", async () => {
    const [clientAToken, clientBToken, dietitianToken] = await Promise.all([
      signIn("client-a@fitnep.test"),
      signIn("client-b@fitnep.test"),
      signIn("dietitian@fitnep.test"),
    ]);
    const created = await workflows.dietPlanAssigned(
      { uid: "dietitian-1", role: "dietitian" },
      { planId: "plan-emulator", clientId: "client-a" },
    );

    const clientAList = await request(api)
      .get("/notifications")
      .set(bearer(clientAToken));
    const clientBList = await request(api)
      .get("/notifications")
      .set(bearer(clientBToken));
    const clientBDirect = await request(api)
      .get(`/notifications/${created.notification.id}`)
      .set(bearer(clientBToken));
    const clientBMark = await request(api)
      .patch(`/notifications/${created.notification.id}/read`)
      .set(bearer(clientBToken));
    const dietitianList = await request(api)
      .get("/notifications")
      .set(bearer(dietitianToken));
    const directFirestoreRead = await fetch(
      firestoreDocumentUrl(created.notification.id),
      { headers: bearer(clientAToken) },
    );
    const directFirestoreWrite = await fetch(
      firestoreDocumentUrl(created.notification.id),
      {
        method: "PATCH",
        headers: {
          ...bearer(clientAToken),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fields: { is_read: { booleanValue: true } },
        }),
      },
    );

    assert.equal(clientAList.status, 200);
    assert.equal(clientAList.body.data.notifications.length, 1);
    assert.equal(clientBList.status, 200);
    assert.deepEqual(clientBList.body.data.notifications, []);
    assert.equal(clientBDirect.status, 404);
    assert.equal(clientBMark.status, 404);
    assert.deepEqual(dietitianList.body.data.notifications, []);
    assert.equal(directFirestoreRead.status, 403);
    assert.equal(directFirestoreWrite.status, 403);
    assert.equal(
      (
        await repository.getForRecipient(
          created.notification.id,
          "client-a",
        )
      )?.isRead,
      false,
    );

    const readAll = await request(api)
      .patch("/notifications/read-all")
      .set(bearer(clientAToken));
    assert.equal(readAll.status, 200);
    assert.equal(readAll.body.data.updated_count, 1);
  });

  it("persists an admin-created package and returns it to clients", async () => {
    const [adminToken, clientToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("client-a@fitnep.test"),
    ]);
    const payload = {
      request_id: "emulator-package-request",
      name: "Six Month Transformation",
      duration_months: 6,
      price: 12500,
      feature_description: "Training, nutrition, and progress reviews.",
    };

    const createResponse = await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send(payload);
    const repeatedResponse = await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send(payload);
    const clientList = await request(api)
      .get("/packages")
      .set(bearer(clientToken));
    const stored = await firestore
      .collection("packages")
      .doc("emulator-package-request")
      .get();

    assert.equal(createResponse.status, 201);
    assert.equal(repeatedResponse.status, 201);
    assert.equal(clientList.status, 200);
    assert.equal(clientList.body.data.packages.length, 1);
    assert.equal(stored.exists, true);
    assert.equal(stored.get("name"), payload.name);
    assert.equal(stored.get("duration_months"), payload.duration_months);
    assert.equal(stored.get("price"), payload.price);
    assert.equal(
      stored.get("feature_description"),
      payload.feature_description,
    );
  });

  it("persists complete package change history with trusted actor and time", async () => {
    const [adminToken, clientToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("client-a@fitnep.test"),
    ]);
    await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send({
        request_id: "audited-emulator-package",
        name: "Premium",
        duration_months: 3,
        price: 5000,
        feature_description: "Diet Plan, Workout Plan",
        admin_id: "forged-admin",
        admin_name: "Forged Name",
        changed_at: "2000-01-01T00:00:00.000Z",
      })
      .expect(201);
    await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send({
        request_id: "audited-emulator-package",
        name: "Premium",
        duration_months: 3,
        price: 5000,
        feature_description: "Diet Plan, Workout Plan",
      })
      .expect(201);
    await request(api)
      .patch("/packages/audited-emulator-package")
      .set(bearer(adminToken))
      .send({
        name: "Premium Plus",
        duration_months: 6,
        price: 6500,
        feature_description:
          "Diet Plan, Workout Plan, Personal Coaching",
      })
      .expect(200);
    await request(api)
      .patch("/packages/audited-emulator-package/active")
      .set(bearer(adminToken))
      .send({ is_active: false })
      .expect(200);
    await request(api)
      .patch("/packages/audited-emulator-package/active")
      .set(bearer(adminToken))
      .send({ is_active: true })
      .expect(200);

    const storedHistory = await firestore
      .collection("package_change_history")
      .where("package_id", "==", "audited-emulator-package")
      .get();
    assert.equal(storedHistory.size, 4);
    const byAction = new Map(
      storedHistory.docs.map((document) => [document.get("action"), document]),
    );
    const created = byAction.get("created");
    const updated = byAction.get("updated");
    const deactivated = byAction.get("deactivated");
    const activated = byAction.get("activated");
    assert.ok(created !== undefined);
    assert.ok(updated !== undefined);
    assert.ok(deactivated !== undefined);
    assert.ok(activated !== undefined);
    assert.equal(created.get("admin_id"), "admin-1");
    assert.equal(created.get("admin_name"), "FitNep CEO");
    assert.ok(created.get("changed_at") instanceof Timestamp);
    assert.deepEqual(updated.get("previous_values"), {
      name: "Premium",
      duration_months: 3,
      price: 5000,
      feature_description: "Diet Plan, Workout Plan",
    });
    assert.deepEqual(updated.get("new_values"), {
      name: "Premium Plus",
      duration_months: 6,
      price: 6500,
      feature_description:
        "Diet Plan, Workout Plan, Personal Coaching",
    });
    assert.deepEqual(deactivated.get("previous_values"), { is_active: true });
    assert.deepEqual(deactivated.get("new_values"), { is_active: false });
    assert.deepEqual(activated.get("previous_values"), { is_active: false });
    assert.deepEqual(activated.get("new_values"), { is_active: true });

    const historyResponse = await request(api)
      .get("/admin/package-history")
      .set(bearer(adminToken))
      .expect(200);
    assert.equal(historyResponse.body.data.history.length, 4);
    await request(api)
      .get("/admin/package-history")
      .set(bearer(clientToken))
      .expect(403);

    const directRead = await fetch(firestorePackageHistoryCollectionUrl(), {
      headers: bearer(clientToken),
    });
    const directWrite = await fetch(
      `${firestorePackageHistoryCollectionUrl()}/forged-history`,
      {
        method: "PATCH",
        headers: {
          ...bearer(clientToken),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fields: {
            admin_id: { stringValue: "forged-admin" },
            changed_at: { timestampValue: "2000-01-01T00:00:00.000Z" },
          },
        }),
      },
    );
    assert.equal(directRead.status, 403);
    assert.equal(directWrite.status, 403);

    const restartedApi = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      packageRepository: new FirestorePackageRepository(firestore),
      purchaseRepository: new FirestorePurchaseRepository(firestore),
    });
    const afterRestart = await request(restartedApi)
      .get("/admin/package-history")
      .set(bearer(adminToken))
      .expect(200);
    assert.equal(afterRestart.body.data.history.length, 4);
  });

  it("keeps customer A's purchased terms after package edits and snapshots new terms for customer B", async () => {
    const [adminToken, clientAToken, clientBToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("client-a@fitnep.test"),
      signIn("client-b@fitnep.test"),
    ]);
    await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send({
        request_id: "premium-emulator-package",
        name: "Premium",
        duration_months: 3,
        price: 5000,
        feature_description: "Diet Plan, Workout Plan, Weekly Consultation",
      })
      .expect(201);

    const customerAPurchase = await request(api)
      .post("/purchases")
      .set(bearer(clientAToken))
      .send({
        package_id: "premium-emulator-package",
        request_id: "customer-a-emulator-purchase",
      })
      .expect(201);

    assert.equal(customerAPurchase.body.data.purchase.status, "pending");
    assert.equal(customerAPurchase.body.data.purchase.purchased_at, null);
    assert.equal(customerAPurchase.body.data.purchase.expires_at, null);
    const approvalPath = `/admin/memberships/${customerAPurchase.body.data.purchase.id}/verify-payment`;
    await request(api).post(approvalPath).set(bearer(clientAToken))
      .send({ reference: "CLIENT-BYPASS" }).expect(403);
    await request(api).post(approvalPath).set(bearer(adminToken))
      .send({ reference: "VERIFIED-A" }).expect(200);
    const activatedA = await request(api).get("/purchases/current")
      .set(bearer(clientAToken)).expect(200);
    assert.equal(activatedA.body.data.purchase.status, "active");

    await request(api)
      .patch("/packages/premium-emulator-package")
      .set(bearer(adminToken))
      .send({
        name: "Premium",
        duration_months: 6,
        price: 6500,
        feature_description:
          "Diet Plan, Workout Plan, Personal Coaching, Priority Consultation",
      })
      .expect(200);

    const customerAAfterEdit = await request(api)
      .get("/purchases/current")
      .set(bearer(clientAToken))
      .expect(200);
    const customerBPurchase = await request(api)
      .post("/purchases")
      .set(bearer(clientBToken))
      .send({
        package_id: "premium-emulator-package",
        request_id: "customer-b-emulator-purchase",
      })
      .expect(201);

    assert.equal(customerAAfterEdit.body.data.purchase.package_name, "Premium");
    assert.equal(customerAAfterEdit.body.data.purchase.price_paid, 5000);
    assert.equal(customerAAfterEdit.body.data.purchase.duration_months, 3);
    assert.equal(
      customerAAfterEdit.body.data.purchase.feature_description,
      "Diet Plan, Workout Plan, Weekly Consultation",
    );
    assert.equal(
      customerAAfterEdit.body.data.purchase.purchased_at,
      activatedA.body.data.purchase.purchased_at,
    );
    assert.equal(
      customerAAfterEdit.body.data.purchase.expires_at,
      activatedA.body.data.purchase.expires_at,
    );
    assert.equal(
      activatedA.body.data.purchase.expires_at,
      addCalendarMonths(
        new Date(activatedA.body.data.purchase.purchased_at as string),
        3,
      ).toISOString(),
    );
    assert.equal(customerBPurchase.body.data.purchase.price_paid, 6500);
    assert.equal(customerBPurchase.body.data.purchase.duration_months, 6);
    assert.equal(
      customerBPurchase.body.data.purchase.feature_description,
      "Diet Plan, Workout Plan, Personal Coaching, Priority Consultation",
    );

    const storedA = await firestore
      .collection("package_memberships")
      .doc(customerAPurchase.body.data.purchase.id as string)
      .get();
    assert.equal(storedA.get("package.price_npr"), 5000);
    assert.equal(storedA.get("package.duration_months"), 3);
    assert.equal(customerBPurchase.body.data.purchase.status, "pending");
    const repeatedSelection = await request(api).post("/memberships")
      .set(bearer(clientBToken))
      .send({ package_id: "premium-emulator-package", request_id: "client-b-shared-selection" })
      .expect(200);
    assert.equal(repeatedSelection.body.data.membership.id, customerBPurchase.body.data.purchase.id);

    const restartedApi = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      packageRepository: new FirestorePackageRepository(firestore),
      purchaseRepository: new FirestorePurchaseRepository(firestore),
    });
    const afterRestart = await request(restartedApi)
      .get("/purchases/current")
      .set(bearer(clientAToken))
      .expect(200);
    assert.equal(afterRestart.body.data.purchase.price_paid, 5000);
    assert.equal(
      afterRestart.body.data.purchase.expires_at,
      activatedA.body.data.purchase.expires_at,
    );
  });
});

async function createAccount(
  auth: Auth,
  uid: string,
  email: string,
  role: UserRole,
  displayName?: string,
): Promise<void> {
  await auth.createUser({
    uid,
    email,
    password: "Password123!",
    ...(displayName === undefined ? {} : { displayName }),
  });
  await auth.setCustomUserClaims(uid, { role });
}

async function signIn(email: string, password = "Password123!"): Promise<string> {
  const response = await fetch(
    `http://${authEmulatorHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email,
        password,
        returnSecureToken: true,
      }),
    },
  );
  const body = (await response.json()) as { idToken?: string };
  if (!response.ok || body.idToken === undefined) {
    throw new Error(`Auth emulator sign-in failed: ${response.status}`);
  }
  return body.idToken;
}

async function clearAuth(): Promise<void> {
  const response = await fetch(
    `http://${authEmulatorHost}/emulator/v1/projects/${projectId}/accounts`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Could not clear Auth emulator: ${response.status}`);
  }
}

async function clearFirestore(): Promise<void> {
  const response = await fetch(
    `http://${firestoreEmulatorHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Could not clear Firestore emulator: ${response.status}`);
  }
}

async function writeSharing(
  uid: string,
  token: string,
  choices: Record<string, boolean | string>,
): Promise<number> {
  const database = `projects/${projectId}/databases/(default)`;
  const fields = Object.fromEntries(Object.entries(choices).map(([key, value]) => [
    key, typeof value === "boolean" ? { booleanValue: value } : { stringValue: value },
  ]));
  const response = await fetch(`http://${firestoreEmulatorHost}/v1/${database}/documents:commit`, {
    method: "POST",
    headers: { ...bearer(token), "Content-Type": "application/json" },
    body: JSON.stringify({
      writes: [{
        update: {
          name: `${database}/documents/privacy_preferences/${uid}`,
          fields,
        },
        updateMask: { fieldPaths: Object.keys(choices) },
        updateTransforms: [{ fieldPath: "updated_at", setToServerValue: "REQUEST_TIME" }],
      }],
    }),
  });
  return response.status;
}

function bearer(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` };
}

function firestoreDocumentUrl(notificationId: string): string {
  return `http://${firestoreEmulatorHost}/v1/projects/${projectId}/databases/(default)/documents/notifications/${notificationId}`;
}

function firestorePackageHistoryCollectionUrl(): string {
  return `http://${firestoreEmulatorHost}/v1/projects/${projectId}/databases/(default)/documents/package_change_history`;
}
