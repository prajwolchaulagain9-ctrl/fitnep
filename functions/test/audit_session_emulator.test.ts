import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import request from "supertest";

import { AuditEventInput, AuditUnavailableError, AuditWriter, FirestoreAuditWriter } from "../src/audit";
import { FirebaseAuthVerifier } from "../src/auth";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
import { FirestorePackageRepository } from "../src/firestore_package_repository";
import { FirestorePurchaseRepository } from "../src/firestore_purchase_repository";
import { createNotificationApp } from "../src/http_app";
import { FirestorePackageService } from "../src/package_membership_service";
import { FirestorePlatformSessionService, platformSessionHeader } from "../src/platform_sessions";
import { FirestorePrivacyAcceptanceStore, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { FirestoreAccountService, FirestoreAuditStore } from "../src/account_service";
import { mountHostedAuth } from "../src/hosted_auth";
import { fork, ChildProcess } from "node:child_process";
import { join } from "node:path";

const projectId = "demo-fitnep";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const emulatorDescribe = authHost && firestoreHost ? describe : describe.skip;
const buildSha = "6f0c245a96be24dcc4e3247e46f5a6e4890b41f6";
const password = "SyntheticFitnep123!";

emulatorDescribe("Day 1 persisted audit and platform sessions", () => {
  let firebase: App;
  let auth: Auth;
  let firestore: Firestore;
  let audit: FirestoreAuditWriter;
  let api: ReturnType<typeof createNotificationApp>;
  let now: number;
  let accounts: FirestoreAccountService;

  function createApi(writer: AuditWriter = audit) {
    return createNotificationApp({
      accounts, audit: new FirestoreAuditStore(firestore),
      authVerifier: new FirebaseAuthVerifier(auth),
      notificationRepository: new FirestoreNotificationRepository(firestore),
      packageService: new FirestorePackageService(firestore),
      packageRepository: new FirestorePackageRepository(firestore),
      purchaseRepository: new FirestorePurchaseRepository(firestore),
      platformSessions: new FirestorePlatformSessionService(firestore, writer, 900, () => new Date(now)),
      auditWriter: writer,
      manualVerificationEnabled: false,
      health: { buildSha, checkReady: async () => { await firestore.doc("_runtime/health").get(); } },
    });
  }

  before(() => {
    assert(/^(127\.0\.0\.1|localhost):\d+$/.test(authHost!));
    assert(/^(127\.0\.0\.1|localhost):\d+$/.test(firestoreHost!));
    firebase = initializeApp({ projectId }, "day1-audit-session-tests");
    auth = getAuth(firebase);
    firestore = getFirestore(firebase);
    audit = new FirestoreAuditWriter(firestore);
    accounts = new FirestoreAccountService(firestore, auth);
  });

  beforeEach(async () => {
    const cleared = await Promise.all([
      fetch("http://" + authHost + "/emulator/v1/projects/" + projectId + "/accounts", { method: "DELETE" }),
      fetch("http://" + firestoreHost + "/emulator/v1/projects/" + projectId + "/databases/(default)/documents", { method: "DELETE" }),
    ]);
    assert(cleared.every(response => response.ok), "synthetic emulator state must be reset");
    for (const [uid, role] of [
      ["day1-client-a", "client"], ["day1-client-b", "client"],
      ["day1-admin", "admin"], ["day1-staff", "staff"],
      ["day1-admin-b", "admin"],
    ]) {
      await auth.createUser({ uid, email: uid + "@fitnep.test", password, emailVerified: true, displayName: uid });
      await auth.setCustomUserClaims(uid!, { role, role_version: 1 });
      await accounts.provision(await auth.getUser(uid!));
      if (role === "client") {
        await new FirestorePrivacyAcceptanceStore(firestore).recordForClient(uid!, {
          age: 21, privacy_policy_accepted: true, privacy_policy_version: privacyPolicyVersion,
        });
      }
    }
    now = Date.parse("2026-11-22T00:00:00Z");
    api = createApi();
  });

  after(async () => { await deleteApp(firebase); });

  async function signIn(uid = "day1-client-a") {
    const response = await fetch("http://" + authHost + "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=synthetic-key", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: uid + "@fitnep.test", password, returnSecureToken: true }),
    });
    assert.equal(response.status, 200);
    return (await response.json() as { idToken: string }).idToken;
  }

  async function start(uid = "day1-client-a", app = api) {
    const token = await signIn(uid);
    const response = await request(app).post("/sessions/start").set("Authorization", "Bearer " + token).send({}).expect(200);
    const sessionId: string = response.body.data.session_id;
    assert(/^[A-Za-z0-9_-]{43}$/.test(sessionId));
    return { token, sessionId, headers: { Authorization: "Bearer " + token, [platformSessionHeader]: sessionId } };
  }

  it("rotates a hosted staff session when its audit grant changes", async () => {
    const admin = await start("day1-admin");
    const staff = await start("day1-staff");
    const auditPath = "/admin/audit-events";
    await request(api).get(auditPath).set(staff.headers).expect(403);
    await request(api).patch("/admin/users/day1-staff").set(admin.headers).send({ audit_read: true }).expect(200);
    const stale = await request(api).get(auditPath).set(staff.headers).expect(401);
    assert.equal(stale.body.code, "session-authority-changed");
    const refreshed = await request(api).post("/sessions/start")
      .set("Authorization", staff.headers.Authorization).send({}).expect(200);
    assert.equal(refreshed.body.data.permissions.audit_read, true);
    assert.equal(refreshed.body.data.permissions.payments_verify, false);
    assert.notEqual(refreshed.body.data.session_id, staff.sessionId);
    const headers = { ...staff.headers, [platformSessionHeader]: refreshed.body.data.session_id };
    await request(api).get(auditPath).set(headers).expect(200);
    await request(api).patch("/admin/users/day1-staff").set(admin.headers).send({ audit_read: false }).expect(200);
    await request(api).get(auditPath).set(headers).expect(401);
  });

  it("a verified session persists server-owned audit metadata and cannot be forged or reopened after logout", async () => {
    await request(api).get("/healthz").expect(200);
    await request(api).post("/sessions/start").send({}).expect(401);
    const session = await start();
    await request(api).get("/packages").set("Authorization", "Bearer " + session.token).expect(401);
    await request(api).get("/packages").set(session.headers).expect(200);
    const initial = await firestore.collection("audit_events").where("action", "==", "session.started").get();
    assert.equal(initial.size, 1);
    const event = initial.docs[0]!.data();
    assert.equal(event.actor_id, "day1-client-a");
    assert.equal(event.actor_name, "day1-client-a");
    assert.equal(event.actor_role, "client");
    assert.equal(event.action, "session.started");
    assert(event.occurred_at instanceof Timestamp);
    assert(!JSON.stringify(event).includes(session.sessionId));
    assert(!JSON.stringify(event).includes(session.token));
    await request(api).post("/sessions/end").set(session.headers).send({}).expect(204);
    await request(api).post("/sessions/end").set(session.headers).send({}).expect(204);
    await request(api).get("/packages").set(session.headers).expect(401);
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + session.token).send({}).expect(401);
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 5);
    // Firebase auth_time has second precision; a fresh authentication must advance it.
    await new Promise(resolve => setTimeout(resolve, 1100));
    const fresh = await start();
    assert(fresh.sessionId !== session.sessionId);
    await request(api).get("/packages").set(fresh.headers).expect(200);
  });

  it("polling, repeated start and API reconstruction do not reset human inactivity", async () => {
    const session = await start();
    const account = firestore.doc("users/day1-client-a");
    const projectedActivity = async () => ((await account.get()).get("last_activity_at") as Timestamp).toMillis();
    const startedAt = now;
    assert.equal(await projectedActivity(), startedAt);
    const first = await request(api).get("/sessions/me").set(session.headers).expect(200);
    const replay = await request(api).post("/sessions/start").set("Authorization", "Bearer " + session.token).send({}).expect(200);
    assert(replay.body.data.session_id === session.sessionId);
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 1);
    now += 30_000;
    const throttled = await request(api).post("/sessions/activity").set(session.headers).send({}).expect(200);
    assert.equal(throttled.body.data.expires_at, first.body.data.expires_at);
    now += 60_000;
    api = createApi();
    const restored = await request(api).get("/sessions/me").set(session.headers).expect(200);
    assert.equal(restored.body.data.expires_at, first.body.data.expires_at);
    assert.equal(await projectedActivity(), startedAt);
    const renewed = await request(api).post("/sessions/activity").set(session.headers).send({}).expect(200);
    assert(Date.parse(renewed.body.data.expires_at) > Date.parse(first.body.data.expires_at));
    assert.equal(await projectedActivity(), now);
    const renewedAt = now;
    now = Date.parse(renewed.body.data.expires_at);
    await request(api).get("/sessions/me").set(session.headers).expect(401);
    await request(api).post("/sessions/activity").set(session.headers).send({}).expect(401);
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + session.token).send({}).expect(401);
    assert.equal(await projectedActivity(), renewedAt);
  });

  it("another UID cannot reuse a session and forbidden requests audit the real actor", async () => {
    const session = await start();
    const other = await signIn("day1-client-b");
    await request(api).get("/packages").set({
      Authorization: "Bearer " + other, [platformSessionHeader]: session.sessionId,
    }).expect(401);
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + session.token)
      .send({ uid: "day1-admin", role: "admin", occurred_at: "forged", session_id: "forged" }).expect(403);
    const denied = await request(api).get("/admin/memberships/pending").set(session.headers)
      .query({ role: "admin", actor: "day1-admin" }).expect(403);
    const events = await firestore.collection("audit_events").where("action", "==", "access.denied").get();
    assert.equal(events.size, 3);
    const ownAttempts = events.docs.filter(event => event.get("actor_id") === "day1-client-a");
    assert.equal(ownAttempts.length, 2);
    assert.equal(events.docs.filter(event => event.get("actor_id") === "day1-client-b").length, 1);
    for (const event of ownAttempts) {
      assert.equal(event.get("actor_id"), "day1-client-a");
      assert.equal(event.get("actor_role"), "client");
      assert(!JSON.stringify(event.data()).includes("forged"));
    }
    assert(events.docs.some(event => event.get("correlation_id") === denied.headers["x-request-id"]));
  });

  it("current role, permission and readiness changes take effect with captured tokens", async () => {
    const admin = await start("day1-admin");
    await request(api).get("/admin/memberships/pending").set(admin.headers).expect(200);
    const operator = { uid: "day1-admin-b", role: "admin" as const };
    await accounts.change(operator, "day1-admin", { role: "staff" });
    await request(api).get("/admin/memberships/pending").set(admin.headers).expect(401);
    const old = await request(api).get("/sessions/me").set(admin.headers).expect(401);
    assert.equal(old.body.code, "session-authority-changed");
    const replacement = await request(api).post("/sessions/start").set("Authorization", "Bearer " + admin.token).send({}).expect(200);
    assert.notEqual(replacement.body.data.session_id, admin.sessionId);
    assert.equal(replacement.body.data.role, "staff");
    assert.equal(replacement.body.data.permissions.audit_read, false);
    const newHeaders = { ...admin.headers, [platformSessionHeader]: replacement.body.data.session_id };
    await request(api).get("/admin/memberships/pending").set(newHeaders).expect(403);
    await request(api).get("/sessions/me").set(admin.headers).expect(401);
    // The limited legacy adapter also resolves the current role, not old JWT claims.
    const legacy = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(auth),
      notificationRepository: new FirestoreNotificationRepository(firestore),
      packageService: new FirestorePackageService(firestore), auditWriter: audit,
    });
    await request(legacy).get("/admin/memberships/pending").set("Authorization", "Bearer " + admin.token).expect(403);
    await auth.setCustomUserClaims("day1-staff", {
      role: "staff", role_version: 1, permissions: { audit_read: true },
    });
    const staff = await start("day1-staff");
    const staffView = await request(api).get("/sessions/me").set(staff.headers).expect(200);
    assert.equal(staffView.body.data.permissions.audit_read, false);
    await accounts.change(operator, "day1-staff", { role: "dietitian" });
    await auth.setCustomUserClaims("day1-staff", { role: "staff", role_version: 1 });
    await request(api).get("/sessions/me").set(staff.headers).expect(401);
    await auth.setCustomUserClaims("day1-staff", { role: "staff", role_version: 2, must_change_password: true });
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + staff.token).send({}).expect(403);
    const client = await start();
    await firestore.doc("privacy_acceptances/day1-client-a").delete();
    await request(api).get("/packages").set(client.headers).expect(403);
  });

  it("the same session survives an actual local Node process restart without renewing expiry", async () => {
    const launch = () => new Promise<{ child: ChildProcess; port: number }>((resolve, reject) => {
      const child = fork(join(__dirname, "fixtures/session_server.js"), [], {
        env: { ...process.env, FITNEP_TEST_NOW: String(now) }, stdio: ["ignore", "ignore", "ignore", "ipc"],
      });
      child.once("error", reject);
      child.once("message", message => resolve({ child, port: (message as { port: number }).port }));
      child.once("exit", code => { if (code !== 0) reject(new Error("Synthetic session server did not start.")); });
    });
    const stop = async (child: ChildProcess) => {
      const exited = new Promise<void>(resolve => child.once("exit", () => resolve()));
      child.kill("SIGTERM"); await exited;
    };
    const token = await signIn();
    let running = await launch();
    try {
      const first = await fetch(`http://127.0.0.1:${running.port}/sessions/start`, {
        method: "POST", headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: "{}",
      });
      assert.equal(first.status, 200);
      const data = (await first.json() as { data: { session_id: string; expires_at: string } }).data;
      const pid = running.child.pid;
      await stop(running.child);
      running = await launch(); assert.notEqual(running.child.pid, pid);
      const restored = await fetch(`http://127.0.0.1:${running.port}/sessions/me`, {
        headers: { Authorization: "Bearer " + token, [platformSessionHeader]: data.session_id },
      });
      assert.equal(restored.status, 200);
      const view = (await restored.json() as { data: { expires_at: string; uid: string } }).data;
      assert.equal(view.uid, "day1-client-a"); assert.equal(view.expires_at, data.expires_at);
      assert.equal((await firestore.collection("audit_events").where("action", "==", "session.started").get()).size, 1);
    } finally { await stop(running.child); }
  });

  it("hosted OTP and consent use the verified owner and preserve onboarding before session start", async () => {
    await auth.updateUser("day1-client-a", { emailVerified: false });
    await firestore.doc("privacy_acceptances/day1-client-a").delete();
    const verifier = new FirebaseAuthVerifier(accounts);
    let deliveredCode = "";
    const hosted = mountHostedAuth(auth, firestore, verifier, {
      BREVO_API_KEY: "synthetic-test-key", SIGNUP_OTP_HASH_SECRET: "synthetic-test-secret-with-32-characters",
      BREVO_SENDER_EMAIL: "sender@fitnep.test",
    }, async (_url, init) => {
      const body = JSON.parse(init?.body as string);
      assert.equal(body.to[0].email, "day1-client-a@fitnep.test");
      deliveredCode = body.textContent.match(/\d{6}/)[0];
      return new Response('{"messageId":"synthetic-accepted-message"}', { status: 201 });
    });
    hosted.use(api);
    const token = await signIn(); const header = { Authorization: "Bearer " + token };
    await request(hosted).post("/sessions/start").set(header).send({}).expect(403);
    await request(hosted).post("/auth/signup/otp/send").set(header).send({ resend: false }).expect(200);
    await request(hosted).post("/auth/signup/otp/verify").set(header).send({ code: deliveredCode }).expect(200);
    assert.equal((await auth.getUser("day1-client-a")).emailVerified, true);
    const verifiedHeader = { Authorization: "Bearer " + await signIn() };
    await request(hosted).post("/auth/privacy").set(verifiedHeader).send({ action: "accept", uid: "day1-client-b",
      age: 21, privacy_policy_version: "1", privacy_policy_accepted: true }).expect(403);
    assert.equal((await firestore.doc("privacy_acceptances/day1-client-b").get()).get("age_at_acceptance"), 21);
    await request(hosted).post("/auth/privacy").set(verifiedHeader).send({ action: "accept", uid: "day1-client-a",
      age: 21, privacy_policy_version: privacyPolicyVersion, privacy_policy_accepted: true }).expect(200);
    await request(hosted).post("/sessions/start").set(verifiedHeader).send({}).expect(200);
  });

  it("saved privacy acceptance and the trusted login lock are required before starting", async () => {
    const token = await signIn();
    const acceptance = firestore.doc("privacy_acceptances/day1-client-a");
    await acceptance.delete();
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + token).send({}).expect(403);
    await acceptance.set({ policy_version: privacyPolicyVersion, accepted_at: Timestamp.now(),
      guardian_consent_confirmed: true });
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + token).send({}).expect(403);
    await acceptance.update({ guardian_consent_confirmed_at: Timestamp.now() });
    await firestore.doc("platform_login_state/day1-client-a").set({
      locked_until: Timestamp.fromMillis(now + 60_000), failed_attempts: 5,
    });
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + token).send({}).expect(403);
    now += 60_001;
    await request(api).post("/sessions/start").set("Authorization", "Bearer " + token).send({}).expect(200);
  });

  it("state, audit and outbox commit together; replay and failures cannot rewrite history", async () => {
    const input: AuditEventInput = {
      actor: { uid: "day1-admin", role: "admin", displayName: "Synthetic Admin" },
      action: "membership.activated", targetType: "membership", targetId: "synthetic-membership",
      clientId: "day1-client-a", outcome: "succeeded", status: "active",
      correlationId: "synthetic-correlation", operationId: "synthetic-operation",
    };
    await firestore.runTransaction(async transaction => {
      transaction.create(firestore.doc("_day1_contract_tests/committed"), { status: "active" });
      audit.appendWithEvent(transaction, input, "membership.activated");
    });
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 1);
    assert.equal((await firestore.collection("workflow_outbox").get()).size, 1);
    assert.equal((await firestore.collection("outbox_deliveries").get()).size, 1);
    await assert.rejects(firestore.runTransaction(async transaction => {
      transaction.set(firestore.doc("_day1_contract_tests/committed"), { status: "replayed" });
      audit.appendWithEvent(transaction, input, "membership.activated");
    }));
    assert.equal((await firestore.doc("_day1_contract_tests/committed").get()).get("status"), "active");
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 1);
    assert.equal((await firestore.collection("workflow_outbox").get()).size, 1);
    await assert.rejects(firestore.runTransaction(async transaction => {
      transaction.create(firestore.doc("_day1_contract_tests/rolled-back"), { status: "active" });
      audit.appendWithEvent(transaction, { ...input, operationId: "failed-operation" }, "membership.activated");
      throw new Error("synthetic transaction failure");
    }));
    assert.equal((await firestore.doc("_day1_contract_tests/rolled-back").get()).exists, false);
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 1);
    assert.equal((await firestore.collection("workflow_outbox").get()).size, 1);
    await assert.rejects(audit.append({ ...input, medical_answers: "must not be accepted" } as AuditEventInput));
    await assert.rejects(audit.append({ ...input, occurred_at: "forged" } as AuditEventInput));
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 1);
  });

  it("audit failure rolls back session creation and a denied response waits for durable auditing", async () => {
    const unavailable: AuditWriter = {
      append: async () => { throw new AuditUnavailableError(); },
      appendInTransaction: () => { throw new AuditUnavailableError(); },
      appendWithEvent: () => { throw new AuditUnavailableError(); },
    };
    const failing = createApi(unavailable);
    const token = await signIn();
    await request(failing).post("/sessions/start").set("Authorization", "Bearer " + token).send({}).expect(503);
    assert.equal((await firestore.collection("platform_sessions").get()).size, 0);
    assert.equal((await firestore.collection("platform_auth_contexts").get()).size, 0);
    const session = await start();
    await request(failing).get("/admin/memberships/pending").set(session.headers).expect(503);
    assert.equal((await firestore.collection("audit_events").where("action", "not-in", ["account.created", "auth.login"]).get()).size, 1);
  });

  it("app accounts cannot append, read, modify or delete audit/session documents through the SDK", async () => {
    const session = await start();
    const admin = await start("day1-admin");
    const events = await firestore.collection("audit_events").get();
    const eventId = events.docs[0]!.id;
    const original = events.docs[0]!.data();
    for (const token of [session.token, admin.token]) {
      const auditUrl = "http://" + firestoreHost + "/v1/projects/" + projectId +
        "/databases/(default)/documents/audit_events/" + eventId;
      const headers = { Authorization: "Bearer " + token, "Content-Type": "application/json" };
      for (const method of ["GET", "PATCH", "DELETE"]) {
        const response = await fetch(auditUrl, {
          method, headers,
          ...(method === "PATCH" ? { body: JSON.stringify({ fields: { action: { stringValue: "forged" } } }) } : {}),
        });
        assert.equal(response.status, 403);
      }
      const created = await fetch(auditUrl + "-forged", {
        method: "PATCH", headers, body: JSON.stringify({ fields: { actor_id: { stringValue: "forged" } } }),
      });
      assert.equal(created.status, 403);
      for (const collection of ["platform_sessions", "platform_auth_contexts", "platform_login_state",
        "workflow_outbox", "outbox_deliveries"]) {
        const response = await fetch("http://" + firestoreHost + "/v1/projects/" + projectId +
          "/databases/(default)/documents/" + collection + "/forged", {
          method: "PATCH", headers, body: JSON.stringify({ fields: { uid: { stringValue: "day1-admin" } } }),
        });
        assert.equal(response.status, 403);
      }
    }
    for (const method of ["post", "patch", "delete"] as const) {
      await request(api)[method]("/audit-events/" + eventId).set(admin.headers).send({ action: "forged" }).expect(404);
    }
    assert.deepEqual((await firestore.doc("audit_events/" + eventId).get()).data(), original);
  });

  it("both purchase projections keep one Pending membership ID and its saved price", async () => {
    await firestore.doc("packages/day1-basic").set({
      name: "Synthetic Basic", duration_months: 1, price: 2500,
      feature_description: "Synthetic package", is_active: true, created_at: Timestamp.now(),
      created_by: "day1-admin", request_id: "day1-catalog-0001",
    });
    const client = await start();
    const selected = await request(api).post("/purchases").set(client.headers)
      .send({ package_id: "day1-basic", request_id: "day1-purchase-0001" }).expect(201);
    const id = selected.body.data.purchase.id;
    const members = await request(api).get("/memberships/me").set(client.headers).expect(200);
    assert.equal(members.body.data.memberships.length, 1);
    assert.equal(members.body.data.memberships[0].id, id);
    const repeat = await request(api).post("/memberships").set(client.headers)
      .send({ package_id: "day1-basic", request_id: "day1-member-00001" }).expect(200);
    assert.equal(repeat.body.data.membership.id, id);
    await firestore.doc("packages/day1-basic").update({ price: 3000 });
    const current = await request(api).get("/purchases/current").set(client.headers).expect(200);
    assert.equal(current.body.data.purchase.id, id);
    assert.equal(current.body.data.purchase.price_paid, 2500);
    assert.equal(current.body.data.purchase.status, "pending");
    assert.equal(current.body.data.purchase.purchased_at, null);
    assert.equal((await firestore.collection("package_memberships").get()).size, 1);
    const admin = await start("day1-admin");
    await request(api).post("/admin/memberships/" + id + "/verify-payment").set(admin.headers)
      .send({ reference: "SYNTHETIC-REFERENCE" }).expect(404);
    assert.equal((await firestore.doc("package_memberships/" + id).get()).get("status"), "pending");
  });
});
