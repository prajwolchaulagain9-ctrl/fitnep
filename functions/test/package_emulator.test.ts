import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import { setTimeout } from "node:timers/promises";
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import request from "supertest";
import { FirebaseAuthVerifier } from "../src/auth";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
import { createNotificationApp } from "../src/http_app";
import { FirestorePackageService, PackageError } from "../src/package_service";

const projectId = "demo-fitnep";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const suite = authHost && firestoreHost ? describe : describe.skip;

suite("US 9 package catalog, selection and verified activation", () => {
  const app = initializeApp({ projectId });
  const db = getFirestore(app);
  const auth = getAuth(app);
  let now = new Date("2026-11-19T06:00:00.000Z");
  const service = new FirestorePackageService(db, () => now);
  const api = createNotificationApp({ authVerifier: new FirebaseAuthVerifier(), notificationRepository: new FirestoreNotificationRepository(db), packageService: service });
  const basic = { active: true, name: "Basic", duration_days: 30, price_npr: 2500, features: ["Personalized nutrition plan", "Weekly check-ins"] };
  let a: string;
  let b: string;
  let admin: string;
  before(async () => {
    for (const [uid, role] of [["package-a", "client"], ["package-b", "client"], ["package-admin", "admin"]] as const) {
      await auth.createUser({ uid, email: `${uid}@example.test`, password: "Password123!" });
      await auth.setCustomUserClaims(uid, { role });
    }
    [a, b, admin] = await Promise.all([token("package-a"), token("package-b"), token("package-admin")]);
  });
  beforeEach(async () => {
    now = new Date("2026-11-19T06:00:00.000Z");
    await fetch(`http://${firestoreHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
    await db.collection("package_catalog").doc("basic").set(basic);
    await db.collection("package_catalog").doc("inactive").set({ ...basic, active: false });
  });
  after(async () => { await deleteApp(app); });

  it("AC1/AC4: returns all active catalog fields and rejects stale selection", async () => {
    const result = await request(api).get("/packages").auth(a, { type: "bearer" });
    assert.equal(result.status, 200);
    assert.deepEqual(result.body.data.packages, [{ id: "basic", name: basic.name, duration_days: 30, price_npr: 2500, features: basic.features }]);
    await db.collection("package_catalog").doc("basic").update({ active: false });
    assert.equal((await choose(a, "stale-selection-0001")).status, 409);
    assert.deepEqual(await service.catalog(), []);
    assert.equal((await request(api).get("/packages")).status, 401);
  });
  it("AC2: persists one Pending snapshot under simultaneous retries and isolates owners", async () => {
    const responses = await Promise.all([choose(a, "same-selection-00001"), choose(a, "same-selection-00001"), choose(a, "next-selection-00001")]);
    assert(responses.every(response => response.status === 200));
    assert.equal(new Set(responses.map(response => response.body.data.membership.id)).size, 1);
    assert.equal(responses[0].body.data.membership.status, "pending");
    assert.equal(responses[0].body.data.membership.start_at, undefined);
    await db.collection("package_catalog").doc("basic").update({ price_npr: 9900 });
    const reloaded = await request(api).get("/memberships/me").auth(a, { type: "bearer" });
    assert.equal(reloaded.body.data.memberships[0].package.price_npr, 2500);
    assert.equal((await db.collection("package_memberships").get()).size, 1);
    assert.equal((await request(api).get("/memberships/me").auth(b, { type: "bearer" })).body.data.memberships.length, 0);
  });
  it("refuses client price/status/identity overrides, activation routes and Firestore bypasses", async () => {
    for (const extra of [{ client_id: "package-b" }, { price_npr: 1 }, { status: "active" }, { start_at: now.toISOString() }, { recipient_id: "package-b" }]) assert.equal((await choose(a, "invalid-selection-01", extra)).status, 400);
    assert.equal((await choose(admin, "admin-selection-001")).status, 403);
    assert.equal((await request(api).post("/memberships/activate").auth(a, { type: "bearer" })).status, 404);
    const member = (await choose(a, "secure-selection-01")).body.data.membership;
    const url = `http://${firestoreHost}/v1/projects/${projectId}/databases/(default)/documents/package_memberships/${member.id}`;
    assert.equal((await fetch(url, { headers: { Authorization: `Bearer ${a}` } })).status, 403);
    assert.equal((await fetch(url, { method: "PATCH", headers: { Authorization: `Bearer ${a}`, "Content-Type": "application/json" }, body: JSON.stringify({ fields: { status: { stringValue: "active" } } }) })).status, 403);
  });
  it("AC2/AC3: verifies payment and observes remaining days, expiry and replay", async () => {
    const member = (await choose(a, "paid-selection-0001")).body.data.membership;
    for (const extra of [{ verified: false }, { status: "pending" }, { amount_npr: 1 }, { recipient_id: "package-b" }, { currency: "USD" }]) {
      await payment("wrong-payment", member.id, extra);
      await assert.rejects(service.activateVerifiedPayment("wrong-payment"), PackageError);
    }
    await payment("correct-payment", member.id);
    const active = await service.activateVerifiedPayment("correct-payment");
    assert.equal(active.status, "active");
    assert.equal(active.start_at, "2026-11-19T06:00:00.000Z");
    assert.equal(active.end_at, "2026-12-19T06:00:00.000Z");
    assert.equal(active.days_remaining, 30);
    assert.deepEqual(await service.activateVerifiedPayment("correct-payment"), active);
    now = new Date("2026-12-19T05:59:59Z");
    assert.equal((await service.memberships("package-a"))[0]!.days_remaining, 1);
    now = new Date(active.end_at!);
    assert.equal((await service.memberships("package-a"))[0]!.status, "expired");
    assert.equal((await service.memberships("package-a"))[0]!.days_remaining, 0);
  });
  it("AC5: serializes competing activations and rejects overlapping dates", async () => {
    const first = (await choose(a, "overlap-selection-01")).body.data.membership;
    const second = { ...first, id: "f".repeat(64) };
    await db.collection("package_memberships").doc(second.id).set(second);
    await payment("payment-first", first.id);
    await payment("payment-second", second.id);
    const results = await Promise.allSettled([service.activateVerifiedPayment("payment-first"), service.activateVerifiedPayment("payment-second")]);
    assert.equal(results.filter(result => result.status === "fulfilled").length, 1);
    assert.equal(results.filter(result => result.status === "rejected").length, 1);
    assert.equal((await service.memberships("package-a")).filter(member => member.status === "active").length, 1);
  });
  it("AC5: permits adjacent scheduled intervals and recognizes the start boundary", async () => {
    const first = (await choose(a, "adjacent-selection-1")).body.data.membership;
    await payment("future-first", first.id, { membership_start_at: "2026-12-01T00:00:00.000Z" });
    const scheduled = await service.activateVerifiedPayment("future-first");
    assert.equal(scheduled.status, "scheduled");
    const second = (await choose(a, "adjacent-selection-2")).body.data.membership;
    await payment("future-second", second.id, { membership_start_at: scheduled.end_at });
    assert.equal((await service.activateVerifiedPayment("future-second")).status, "scheduled");
    now = new Date(scheduled.start_at!);
    const members = await service.memberships("package-a");
    assert.equal(members.find(member => member.id === first.id)?.days_remaining, 30);
    assert.equal(members.find(member => member.id === second.id)?.status, "scheduled");
  });
  it("rejects malformed catalogs and revoked Firebase session tokens", async () => {
    await db.collection("package_catalog").doc("basic").update({ price_npr: -1 });
    assert.equal((await request(api).get("/packages").auth(a, { type: "bearer" })).status, 503);
    await setTimeout(1100);
    await auth.revokeRefreshTokens("package-a");
    assert.equal((await request(api).get("/memberships/me").auth(a, { type: "bearer" })).status, 401);
    assert.equal((await choose(a, "revoked-selection-01")).status, 401);
  });
  it("fails closed when an existing active membership has malformed dates", async () => {
    // The prior test revoked client A; use the trusted operation for this fixture.
    const member = await service.select("package-a", "basic", "corrupt-selection-01");
    const corrupt = db.collection("package_memberships").doc("e".repeat(64));
    await corrupt.set({ ...member, id: corrupt.id, status: "active", start_at: "invalid", end_at: now.toISOString() });
    await payment("corrupt-payment", member.id);
    await assert.rejects(service.activateVerifiedPayment("corrupt-payment"), /needs attention/);
    await corrupt.update({ start_at: new Date(now.getTime() + 86_400_000).toISOString() });
    await assert.rejects(service.activateVerifiedPayment("corrupt-payment"), /needs attention/);
    assert.equal((await db.collection("package_memberships").doc(member.id).get()).get("status"), "pending");
  });
  function choose(token: string, id: string, extra = {}) { return request(api).post("/memberships").auth(token, { type: "bearer" }).send({ package_id: "basic", request_id: id, ...extra }); }
  async function payment(id: string, membership: string, extra = {}) { await db.collection("payments").doc(id).set({ membership_id: membership, recipient_id: "package-a", amount_npr: 2500, currency: "NPR", status: "paid", verified: true, ...extra }); }
});

async function token(uid: string): Promise<string> {
  const response = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email: `${uid}@example.test`, password: "Password123!", returnSecureToken: true }) });
  const data = await response.json() as { idToken?: string };
  assert(response.ok && data.idToken);
  return data.idToken;
}
