import assert from "node:assert/strict";
import { before, beforeEach, after, describe, it } from "node:test";
import { getAuth, Auth } from "firebase-admin/auth";
import { getFirestore, Firestore, Timestamp } from "firebase-admin/firestore";
import { initializeApp, deleteApp, App } from "firebase-admin/app";
import request from "supertest";
import { FirestoreAccountService } from "../src/account_service";
import { createNotificationApp } from "../src/http_app";
import { FirestorePrivateRecordsStore } from "../src/firestore_private_records_store";
import { FirestorePrivacyAcceptanceStore, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { AuditUnavailableError } from "../src/audit";
import { UserRole } from "../src/domain";
import { createFitnepApi, createFitnepDependencies } from "../src/api_factory";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const dbHost = process.env.FIRESTORE_EMULATOR_HOST;
const project = "demo-fitnep";
const suite = authHost && dbHost ? describe : describe.skip;
suite("RBAC with real Firebase identities, Firestore transactions and rules", () => {
  let app: App, auth: Auth, db: Firestore, accounts: FirestoreAccountService;
  let api: ReturnType<typeof createNotificationApp>;
  let tokens: Record<string, string>;
  before(() => {
    assert.match(authHost!, /^(127\.0\.0\.1|localhost):\d+$/);
    assert.match(dbHost!, /^(127\.0\.0\.1|localhost):\d+$/);
    app = initializeApp({ projectId: project }); auth = getAuth(app); db = getFirestore(app);
    const dependencies = createFitnepDependencies(auth, db);
    accounts = dependencies.accounts;
    api = createNotificationApp(dependencies);
  });
  beforeEach(async () => {
    await fetch("http://" + authHost + "/emulator/v1/projects/" + project + "/accounts", { method: "DELETE" });
    await fetch("http://" + dbHost + "/emulator/v1/projects/" + project + "/databases/(default)/documents", { method: "DELETE" });
    tokens = {};
    for (const [uid, role] of [["ceo", "admin"], ["staff", "staff"], ["dietitian", "dietitian"],
      ["client", "client"], ["other", "client"]] as [string, UserRole][]) {
      await auth.createUser({ uid, email: uid + "@fitnep.test", password: "Password!123", emailVerified: true });
      await auth.setCustomUserClaims(uid, { role });
      await accounts.provision(await auth.getUser(uid));
      if (role === "client") await new FirestorePrivacyAcceptanceStore(db).recordForClient(uid, {
        age: 21, privacy_policy_accepted: true, privacy_policy_version: privacyPolicyVersion,
      });
      const signedIn = await fetch("http://" + authHost + "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: uid + "@fitnep.test", password: "Password!123", returnSecureToken: true }),
      });
      tokens[uid] = (await signedIn.json() as { idToken: string }).idToken;
    }
    await activatePackage();
  });
  async function activatePackage() {
    await db.collection("customer_purchases").doc("client").collection("purchases").doc("active-package").set({
      is_active: true, purchased_at: Timestamp.fromMillis(Date.now() - 86_400_000),
      expires_at: Timestamp.fromMillis(Date.now() + 86_400_000),
    });
  }
  after(async () => { await deleteApp(app); });
  const bearer = (uid: string) => ({ Authorization: "Bearer " + tokens[uid] });
  const denied = (response: { status: number; body: { code?: string } }) => {
    assert.equal(response.status, 403); assert.equal(response.body.code, "permission-denied");
  };
  it("registers a default client role from Firebase identity without accepting client role input", async () => {
    const identity = await auth.createUser({ uid: "new", email: "new@fitnep.test", password: "Password!123" });
    const [first, second] = await Promise.all([accounts.provision(identity), accounts.provision(identity)]);
    assert.equal(first.role, "client"); assert.deepEqual(first, second);
    const data = (await db.collection("users").doc("new").get()).data()!;
    assert.equal(data.role, "client"); assert(data.created_at instanceof Timestamp);
    for (const role of ["", "owner", null, ["client", "admin"]]) {
      await db.collection("users").doc("client").update({ role });
      denied(await request(api).get("/session").set(bearer("client")));
    }
  });
  it("rejects clients, staff and dietitians at administrative endpoints and logs all attempts", async () => {
    for (const uid of ["client", "staff", "dietitian"]) {
      denied(await request(api).get("/admin/users").set(bearer(uid)));
      denied(await request(api).patch("/admin/users/other").set(bearer(uid)).send({ role: "admin" }));
      denied(await request(api).get("/admin/audit-logs").set(bearer(uid)));
    }
    const logs = await db.collection("audit_logs").get();
    assert.equal(logs.size, 9);
    for (const log of logs.docs) {
      assert.equal(log.get("result"), "DENIED");
      assert(["client", "staff", "dietitian"].includes(log.get("user_id")));
      assert.equal(log.get("current_role"), log.get("user_id"));
      assert(log.get("timestamp") instanceof Timestamp);
      assert(log.get("action")); assert(log.get("resource"));
      assert.equal(JSON.stringify(log.data()).includes(tokens.client!), false);
    }
    await request(api).get("/admin/users").set(bearer("ceo")).expect(200);
    await request(api).get("/admin/audit-logs").set(bearer("ceo")).expect(200);
  });
  it("rejects administrative URL aliases and implicit HEAD requests, and audits every denial", async () => {
    const paths = ["/ADMIN/USERS", "/Admin/Users/", "/ADMIN/USERS/other",
      "/ADMIN/CLIENTS/", "/ADMIN/CLIENTS/client", "/ADMIN/CLIENTS/client/assignment/",
      "/ADMIN/AUDIT-LOGS/"];
    for (const uid of ["client", "staff", "dietitian"]) {
      for (const path of paths) denied(await request(api).get(path).set(bearer(uid)));
      const head = await request(api).head("/ADMIN/AUDIT-LOGS/").set(bearer(uid)).expect(403);
      assert.equal(head.text ?? "", "");
      denied(await request(api).get("/ADMIN/unconfigured-feature/").set(bearer(uid)));
    }
    const logs = await db.collection("audit_logs").get();
    assert.equal(logs.size, 3 * (paths.length + 2));
    for (const log of logs.docs) {
      assert.equal(log.get("result"), "DENIED");
      assert.equal(log.get("current_role"), log.get("user_id"));
      assert(log.get("timestamp") instanceof Timestamp);
      assert(log.get("action")); assert(log.get("resource"));
      assert(!JSON.stringify(log.data()).includes("Bearer"));
    }
    assert(logs.docs.some(log => log.get("action") === "view_audit_logs" && log.get("resource") === "authorization_audit"));
    for (const path of paths) await request(api).get(path).set(bearer("ceo")).expect(200);
    await request(api).head("/ADMIN/USERS/").set(bearer("ceo")).expect(200);
  });
  it("blocks self escalation and ordinary profile role/status edits", async () => {
    denied(await request(api).patch("/profile/me").set(bearer("client")).send({ role: "admin" }));
    denied(await request(api).patch("/admin/users/ceo").set(bearer("ceo")).send({ role: "client" }));
    denied(await request(api).patch("/admin/users/ceo").set(bearer("ceo")).send({ account_status: "inactive" }));
    await request(api).patch("/profile/me").set(bearer("client")).send({ full_name: "Updated Client" }).expect(200);
    assert.equal((await accounts.get("client")).role, "client");
    for (const role of [null, "", "CEO", ["client", "staff"]]) {
      await request(api).patch("/admin/users/client").set(bearer("ceo")).send({ role }).expect(400);
    }
  });
  it("applies a role change on the next request using the SAME old ID token and audits before/after", async () => {
    const tokenBefore = tokens.staff;
    denied(await request(api).get("/admin/users").set(bearer("staff")));
    denied(await request(api).get("/ADMIN/USERS/").set(bearer("staff")));
    await request(api).patch("/admin/users/staff").set(bearer("ceo")).send({ role: "admin" }).expect(200);
    assert.equal(tokens.staff, tokenBefore);
    await request(api).get("/admin/users").set(bearer("staff")).expect(200);
    await request(api).get("/ADMIN/USERS/").set(bearer("staff")).expect(200);
    await request(api).head("/ADMIN/USERS/").set(bearer("staff")).expect(200);
    await request(api).patch("/admin/users/staff").set(bearer("ceo")).send({ role: "client" }).expect(200);
    denied(await request(api).get("/admin/users").set(bearer("staff")));
    denied(await request(api).get("/ADMIN/USERS/").set(bearer("staff")));
    await request(api).head("/ADMIN/USERS/").set(bearer("staff")).expect(403);
    const session = await request(api).get("/session").set(bearer("staff")).expect(200);
    assert.equal(session.body.data.account.role, "client");
    assert(session.body.data.permissions.includes("manage_own_membership"));
    assert(!session.body.data.permissions.includes("manage_user_roles"));
    const logs = await db.collection("audit_logs").where("result", "==", "ALLOWED").get();
    assert.equal(logs.size, 2);
    const changes = logs.docs.map(doc => doc.data());
    assert(changes.some(row => row.previous_role === "staff" && row.new_role === "admin"));
    assert(changes.some(row => row.previous_role === "admin" && row.new_role === "client"));
    for (const row of changes) { assert.equal(row.user_id, "ceo"); assert.equal(row.record_id, "staff"); assert(row.timestamp instanceof Timestamp); }
  });
  it("deactivation denies the next request and activation restores the account", async () => {
    await request(api).patch("/admin/users/staff").set(bearer("ceo")).send({ account_status: "inactive" }).expect(200);
    denied(await request(api).get("/session").set(bearer("staff")));
    denied(await request(api).get("/notifications").set(bearer("staff")));
    await request(api).head("/NOTIFICATIONS/").set(bearer("staff")).expect(403);
    const ownDoc = "http://" + dbHost + "/v1/projects/" + project + "/databases/(default)/documents/users/staff";
    assert.equal((await fetch(ownDoc, { headers: bearer("staff") })).status, 403);
    await request(api).patch("/admin/users/staff").set(bearer("ceo")).send({ account_status: "active" }).expect(200);
    await request(api).get("/session").set(bearer("staff")).expect(200);
  });
  it("enforces assignment, role revision, owner identity and consent before reading records", async () => {
    const assignment = "/admin/clients/client/assignment";
    await request(api).put(assignment).set(bearer("ceo")).send({ dietitian_id: "dietitian", staff_ids: ["staff"] }).expect(200);
    const assigned = await request(api).get("/clients/assigned").set(bearer("staff")).expect(200);
    assert.deepEqual(assigned.body.data.clients.map((row: { id: string }) => row.id), ["client"]);
    await request(api).get("/clients/client/profile").set(bearer("staff")).expect(200);
    denied(await request(api).get("/clients/other/profile").set(bearer("staff")));
    const path = "/clients/client/records/nutrition-records";
    await request(api).post(path).set(bearer("client")).send({ food_name: "Rice", calories: 250 }).expect(201);
    await request(api).get(path).set(bearer("client")).expect(200);
    for (const uid of ["other", "staff", "ceo", "dietitian"]) denied(await request(api).get(path).set(bearer(uid)));
    await request(api).patch("/privacy/preferences").set(bearer("client")).send({ share_nutrition_records: true }).expect(200);
    await request(api).get(path).set(bearer("dietitian")).expect(200);
    await request(api).get(path).set(bearer("staff")).expect(200);
    await request(api).patch("/admin/users/dietitian").set(bearer("ceo")).send({ role: "staff" }).expect(200);
    denied(await request(api).get(path).set(bearer("dietitian")));
    await request(api).patch("/admin/users/dietitian").set(bearer("ceo")).send({ role: "dietitian" }).expect(200);
    denied(await request(api).get(path).set(bearer("dietitian"))); // old assignment remains revoked
    await request(api).put(assignment).set(bearer("ceo")).send({ dietitian_id: "dietitian", staff_ids: ["staff"] }).expect(200);
    await request(api).get(path).set(bearer("dietitian")).expect(200);
    await request(api).patch("/privacy/preferences").set(bearer("client")).send({ share_nutrition_records: false }).expect(200);
    denied(await request(api).get(path).set(bearer("dietitian")));
  });
  it("enforces record ownership for case variants, trailing slashes and HEAD requests", async () => {
    await request(api).post("/clients/client/records/nutrition-records").set(bearer("client"))
      .send({ food_name: "Rice", calories: 250 }).expect(201);
    for (const path of ["/clients/client/records/nutrition-records/", "/CLIENTS/client/RECORDS/nutrition-records/"]) {
      const owned = await request(api).get(path).set(bearer("client")).expect(200);
      assert.equal(owned.body.data.records.length, 1);
      denied(await request(api).get(path).set(bearer("other")));
      await request(api).head(path).set(bearer("other")).expect(403);
      await request(api).head(path).set(bearer("client")).expect(200);
    }
    const data = { sender_id: "client", recipient_id: "client", assignee_id: "client",
      participant_ids: ["client"], title: "Owned record", body: "Private content" };
    for (const collection of ["payments", "tasks", "conversations", "messages"]) {
      await db.collection(collection).doc("MixedCase_Record").set(data);
      const path = "/" + collection.toUpperCase() + "/MixedCase_Record/";
      await request(api).get(path).set(bearer("client")).expect(200);
      for (const uid of ["other", "staff", "dietitian"]) {
        denied(await request(api).get(path).set(bearer(uid)));
        await request(api).head(path).set(bearer(uid)).expect(403);
      }
    }
  });
  it("invalidates care-team grants after client role/status changes even with unchanged tokens", async () => {
    const assignment = "/admin/clients/client/assignment";
    const team = { dietitian_id: "dietitian", staff_ids: ["staff"] };
    await request(api).put(assignment).set(bearer("ceo")).send(team).expect(200);
    await request(api).patch("/privacy/preferences").set(bearer("client"))
      .send({ share_nutrition_records: true }).expect(200);
    const records = "/CLIENTS/client/RECORDS/nutrition-records/";
    const profile = "/CLIENTS/client/PROFILE/";
    await request(api).get(records).set(bearer("dietitian")).expect(200);
    await request(api).get(profile).set(bearer("staff")).expect(200);
    const before = { client: tokens.client, staff: tokens.staff, dietitian: tokens.dietitian };
    await request(api).patch("/admin/users/client").set(bearer("ceo")).send({ role: "staff" }).expect(200);
    denied(await request(api).get(records).set(bearer("client")));
    denied(await request(api).get(records).set(bearer("dietitian")));
    await request(api).patch("/admin/users/client").set(bearer("ceo")).send({ role: "client" }).expect(200);
    denied(await request(api).get(records).set(bearer("dietitian")));
    denied(await request(api).get(profile).set(bearer("staff")));
    await request(api).get(records).set(bearer("client")).expect(200);
    await request(api).put(assignment).set(bearer("ceo")).send(team).expect(200);
    await request(api).get(records).set(bearer("dietitian")).expect(200);
    await request(api).get(profile).set(bearer("staff")).expect(200);
    await request(api).patch("/admin/users/client").set(bearer("ceo"))
      .send({ account_status: "inactive" }).expect(200);
    for (const uid of ["client", "dietitian"]) denied(await request(api).get(records).set(bearer(uid)));
    denied(await request(api).get(profile).set(bearer("staff")));
    assert.deepEqual({ client: tokens.client, staff: tokens.staff, dietitian: tokens.dietitian }, before);
  });
  it("only an assigned dietitian can create/edit plans, and only authorized accounts can read them", async () => {
    await request(api).put("/admin/clients/client/assignment").set(bearer("ceo"))
      .send({ dietitian_id: "dietitian", staff_ids: ["staff"] }).expect(200);
    await request(api).get("/clients/client/profile").set(bearer("staff")).expect(200);
    const path = "/clients/client/diet-plans";
    const fields = { title: "Week one", description: "Daily nutrition plan." };
    for (const uid of ["client", "staff", "ceo"]) denied(await request(api).post(path).set(bearer(uid)).send(fields));
    denied(await request(api).post("/clients/other/diet-plans").set(bearer("dietitian")).send(fields));
    const created = await request(api).post(path).set(bearer("dietitian")).send(fields).expect(201);
    const id = created.body.data.plan.id as string;
    await request(api).patch(path + "/" + id).set(bearer("dietitian")).send({ ...fields, title: "Updated plan" }).expect(200);
    await request(api).get("/diet-plans/" + id).set(bearer("client")).expect(200);
    denied(await request(api).get("/diet-plans/" + id).set(bearer("dietitian")));
    await request(api).patch("/privacy/preferences").set(bearer("client"))
      .send({ share_nutrition_records: true }).expect(200);
    await request(api).get("/DIET-PLANS/" + id + "/").set(bearer("dietitian")).expect(200);
    for (const uid of ["other", "ceo"]) denied(await request(api).get("/diet-plans/" + id).set(bearer(uid)));
    for (const path of ["/clients/client/diet-plans", "/CLIENTS/client/DIET-PLANS/", "/DIET-PLANS/" + id + "/"]) {
      await request(api).get(path).set(bearer("staff")).expect(200);
      await request(api).head(path).set(bearer("staff")).expect(200);
      await request(api).get(path).set(bearer("client")).expect(200);
    }
    await request(api).patch("/privacy/preferences").set(bearer("client"))
      .send({ share_nutrition_records: false }).expect(200);
    for (const uid of ["staff", "dietitian"]) {
      denied(await request(api).get("/diet-plans/" + id).set(bearer(uid)));
      denied(await request(api).get(path).set(bearer(uid)));
    }
  });
  it("denies direct Firestore role escalation, other-account reads and audit writes/deletes", async () => {
    const base = "http://" + dbHost + "/v1/projects/" + project + "/databases/(default)/documents/";
    const headers = { ...bearer("client"), "Content-Type": "application/json" };
    assert.equal((await fetch(base + "users/client", { headers })).status, 403);
    const signal = await fetch(base + "account_access/client", { headers });
    assert.equal(signal.status, 200);
    const signalJson = JSON.stringify(await signal.json());
    assert(!signalJson.includes("full_name") && !signalJson.includes("account_status"));
    assert.equal((await fetch(base + "account_access/other", { headers })).status, 403);
    assert.equal((await fetch(base + "users/other", { headers })).status, 403);
    assert.equal((await fetch(base + "users/client?updateMask.fieldPaths=role", { method: "PATCH", headers,
      body: JSON.stringify({ fields: { role: { stringValue: "admin" } } }) })).status, 403);
    const id = (await db.collection("audit_logs").add({ timestamp: Timestamp.now(), result: "DENIED" })).id;
    for (const method of ["GET", "DELETE", "PATCH"]) {
      assert.equal((await fetch(base + "audit_logs/" + id, { method, headers,
        ...(method === "PATCH" ? { body: JSON.stringify({ fields: { result: { stringValue: "ALLOWED" } } }) } : {}) })).status, 403);
    }
    assert.equal((await accounts.get("client")).role, "client");
  });
  it("blocks unverified email accounts from protected data while keeping account provisioning available", async () => {
    await auth.updateUser("client", { emailVerified: false });
    // Force a new sign-in so this is a genuine unverified Firebase token.
    const response = await fetch("http://" + authHost + "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "client@fitnep.test", password: "Password!123", returnSecureToken: true }),
    });
    tokens.client = (await response.json() as { idToken: string }).idToken;
    for (const path of ["/session", "/SESSION/", "/PROFILE/ME/"]) {
      await request(api).get(path).set(bearer("client")).expect(200);
    }
    await request(api).patch("/PROFILE/ME/").set(bearer("client")).send({ full_name: "Unverified Client" }).expect(200);
    await request(api).post("/AUTHORIZATION/CHECK/").set(bearer("client")).send({ permission: "view_dashboard" }).expect(200);
    denied(await request(api).post("/AUTHORIZATION/CHECK/").set(bearer("client")).send({ permission: "manage_user_roles" }));
    for (const path of ["/notifications", "/NOTIFICATIONS/", "/CLIENTS/client/RECORDS/nutrition-records/"]) {
      denied(await request(api).get(path).set(bearer("client")));
      await request(api).head(path).set(bearer("client")).expect(403);
    }
  });
  it("the serverless host adapter enforces the same backend permissions", async () => {
    const hosted = createFitnepApi();
    denied(await request(hosted).get("/admin/users").set(bearer("staff")));
    denied(await request(hosted).get("/ADMIN/USERS/").set(bearer("staff")));
    await request(hosted).head("/ADMIN/AUDIT-LOGS/").set(bearer("staff")).expect(403);
    await request(hosted).get("/admin/users").set(bearer("ceo")).expect(200);
    await request(hosted).get("/ADMIN/USERS/").set(bearer("ceo")).expect(200);
  });
  it("audit resources and IDs never copy credential-like paths", async () => {
    const credential = "xkeysib-" + "a".repeat(60);
    denied(await request(api).patch("/admin/users/" + credential).set(bearer("client")).send({ role: "admin" }));
    const logs = await db.collection("audit_logs").get();
    assert.equal(logs.size, 1);
    assert.equal(logs.docs[0]!.get("resource"), "admin_user_management");
    assert.equal(logs.docs[0]!.get("record_id"), null);
    assert(!JSON.stringify(logs.docs[0]!.data()).includes(credential));
  });
  it("checks each workflow's owner fields and restricts financial data to its owner or authorized business admin", async () => {
    const data = { sender_id: "staff", recipient_id: "client", assignee_id: "client",
      participant_ids: ["client", "other"], title: "Protected record", body: "Record details" };
    for (const collection of ["payments", "tasks", "conversations", "messages"]) {
      await db.collection(collection).doc("record").set(data);
    }
    for (const collection of ["payments", "tasks", "conversations"]) {
      denied(await request(api).get("/" + collection + "/record").set(bearer("staff")));
    }
    denied(await request(api).get("/messages/record").set(bearer("staff")));
    denied(await request(api).get("/conversations/record").set(bearer("client"))); // two client owners are ambiguous
    await db.collection("messages").doc("record").update({ client_id: "client" });
    await request(api).put("/admin/clients/client/assignment").set(bearer("ceo"))
      .send({ dietitian_id: "dietitian", staff_ids: ["staff"] }).expect(200);
    await request(api).patch("/privacy/preferences").set(bearer("client"))
      .send({ share_nutrition_records: true }).expect(200);
    await request(api).get("/messages/record").set(bearer("staff")).expect(200);
    await request(api).get("/payments/record").set(bearer("client")).expect(200);
    await request(api).get("/payments/record").set(bearer("ceo")).expect(200);
  });
  it("shares package eligibility and account revisions across both assignment APIs", async () => {
    const legacy = "/admin/clients/client/assignment";
    const current = "/admin/client-assignments/client";
    const team = { dietitian_id: "dietitian", staff_ids: ["staff"] };
    await db.doc("customer_purchases/client/purchases/active-package").delete();
    const ineligible = await request(api).get(current + "/eligibility").set(bearer("ceo")).expect(200);
    assert.equal(ineligible.body.data.eligibility.can_assign, false);
    await request(api).put(legacy).set(bearer("ceo")).send(team).expect(409);
    await request(api).put(current).set(bearer("ceo")).send({ dietitian_id: "dietitian" }).expect(409);
    assert.equal((await db.doc("client_assignments/client").get()).exists, false);
    await activatePackage();
    await request(api).put(legacy).set(bearer("ceo")).send(team).expect(200);
    const version = (await db.doc("client_assignments/client").get()).get("version");
    await request(api).put(current).set(bearer("ceo")).send({ dietitian_id: "dietitian" }).expect(200);
    assert.equal((await db.doc("client_assignments/client").get()).get("version"), version);
    assert.deepEqual((await db.doc("client_assignments/client").get()).get("team_member_ids"), ["staff"]);
    await request(api).get("/dietitian/assigned-clients/client").set(bearer("dietitian")).expect(200);
    const counts = async () => (await request(api).get("/admin/client-assignments/dietitian-counts")
      .set(bearer("ceo")).expect(200)).body.data.counts;
    assert.deepEqual(await counts(), { dietitian: 1 });
    await request(api).patch("/admin/users/dietitian").set(bearer("ceo"))
      .send({ account_status: "inactive" }).expect(200);
    assert.deepEqual(await counts(), {});
    const inactiveProfile = await request(api).get("/admin/clients/client").set(bearer("ceo")).expect(200);
    assert.equal(inactiveProfile.body.data.client.assignedDietitianId, "");
    denied(await request(api).get("/clients/client/profile").set(bearer("staff")));
    await request(api).patch("/admin/users/dietitian").set(bearer("ceo"))
      .send({ account_status: "active" }).expect(200);
    assert.deepEqual(await counts(), {}); // reactivation cannot revive the old grant
    denied(await request(api).get("/dietitian/assigned-clients/client").set(bearer("dietitian")));
    await request(api).put(current).set(bearer("ceo")).send({ dietitian_id: "dietitian" }).expect(200);
    assert.deepEqual(await counts(), { dietitian: 1 });
    assert.deepEqual((await db.doc("client_assignments/client").get()).get("team_member_ids"), []);
    denied(await request(api).get("/clients/client/profile").set(bearer("staff")));
    await request(api).put(legacy).set(bearer("ceo")).send(team).expect(200);
    await request(api).get("/dietitian/assigned-clients/client").set(bearer("dietitian")).expect(200);
    await request(api).get("/clients/client/profile").set(bearer("staff")).expect(200);
    await request(api).patch("/admin/users/client").set(bearer("ceo"))
      .send({ account_status: "inactive" }).expect(200);
    assert.deepEqual(await counts(), {});
    denied(await request(api).get("/dietitian/assigned-clients/client").set(bearer("dietitian")));
  });
  it("audits plans and conversations before returning content and revokes stale support grants", async () => {
    await request(api).put("/admin/clients/client/assignment").set(bearer("ceo"))
      .send({ dietitian_id: "dietitian", staff_ids: ["staff"] }).expect(200);
    await db.doc("client_assignments/client").update({
      team_member_ids: ["staff", "ceo"], team_member_role_revisions: { staff: 0, ceo: 0 },
    });
    await request(api).patch("/privacy/preferences").set(bearer("client"))
      .send({ share_nutrition_records: true }).expect(200);
    await db.doc("diet_plans/plan").set({ client_id: "client", title: "Clinical plan", description: "Sensitive plan details" });
    await db.doc("conversations/thread").set({ client_id: "client",
      participant_ids: ["client", "dietitian", "staff", "ceo"], body: "Sensitive conversation" });
    const paths = ["/clients/client/diet-plans", "/diet-plans/plan", "/conversations/thread"];
    for (const uid of ["client", "dietitian", "staff", "ceo"]) {
      for (const path of paths) {
        const result = await request(api).get(path).set(bearer(uid)).expect(200);
        const events = await db.collection("audit_events").where("correlation_id", "==", result.headers["x-request-id"]).get();
        assert.equal(events.size, 1);
        const event = events.docs[0]!;
        assert.equal(event.get("actor_id"), uid);
        assert.equal(event.get("action"), "health.read");
        assert.equal(event.get("client_id"), "client");
        assert(!JSON.stringify(event.data()).includes("Sensitive"));
        if (path === paths[0]) assert.deepEqual(event.get("record_ids"), ["plan"]);
      }
    }
    for (const path of paths) denied(await request(api).get(path).set(bearer("other")));
    const dependencies = createFitnepDependencies(auth, db);
    const unavailable = createNotificationApp({ ...dependencies,
      privateRecordsStore: new FirestorePrivateRecordsStore(db, dependencies.privacyPreferencesRepository, {
        appendInTransaction() { throw new AuditUnavailableError(); },
      }),
    });
    const successfulReads = await db.collection("audit_events").where("action", "==", "health.read").get();
    for (const path of paths) {
      const result = await request(unavailable).get(path).set(bearer("staff")).expect(503);
      assert(!JSON.stringify(result.body).includes("Sensitive"));
    }
    assert.equal((await db.collection("audit_events").where("action", "==", "health.read").get()).size, successfulReads.size);
    await request(api).patch("/admin/users/staff").set(bearer("ceo")).send({ role: "client" }).expect(200);
    await request(api).patch("/admin/users/staff").set(bearer("ceo")).send({ role: "staff" }).expect(200);
    for (const path of paths) denied(await request(api).get(path).set(bearer("staff")));
    await db.doc("privacy_acceptances/client").update({ policy_version: "1" });
    for (const uid of ["dietitian", "ceo"]) {
      for (const path of paths) denied(await request(api).get(path).set(bearer(uid)));
    }
    await request(api).get(paths[1]!).set(bearer("client")).expect(200);
  });
  it("previews and applies migration without overwriting existing roles", async () => {
    await auth.createUser({ uid: "legacy", email: "legacy@fitnep.test", password: "Password!123" });
    await auth.setCustomUserClaims("legacy", { role: "staff" });
    const execute = promisify(execFile);
    const preview = await execute(process.execPath, ["scripts/migrate-rbac.cjs", "--project=" + project]);
    assert.match(preview.stdout, /"mode":"preview"/);
    assert.equal((await db.collection("users").doc("legacy").get()).exists, false);
    const applied = await execute(process.execPath, ["scripts/migrate-rbac.cjs", "--project=" + project, "--apply"]);
    assert.match(applied.stdout, /"migrated":1/);
    assert.equal((await accounts.get("legacy")).role, "staff");
    assert.equal((await accounts.get("ceo")).role, "admin");
    await assert.rejects(execute(process.execPath, ["scripts/migrate-rbac.cjs", "--project=" + project,
      "--apply", "--bootstrap-admin=client"]));
    assert.equal((await accounts.get("client")).role, "client");
    await db.collection("users").doc("ceo").update({ role: "client" });
    await execute(process.execPath, ["scripts/migrate-rbac.cjs", "--project=" + project,
      "--apply", "--bootstrap-admin=client"]);
    assert.equal((await accounts.get("client")).role, "admin");
    assert.equal((await accounts.get("ceo")).role, "client");
  });
});
