import assert from "node:assert/strict";
import { it } from "node:test";
import request from "supertest";
import { Auth } from "firebase-admin/auth";
import { Firestore } from "firebase-admin/firestore";
import { mountHostedAuth } from "../src/hosted_auth";
import { AuthenticationError } from "../src/auth";

const auth = {} as Auth; const firestore = {} as Firestore;
const verifier = { verifyIdToken: async () => { throw new AuthenticationError("No test identity."); } };
const environment = { FIREBASE_WEB_API_KEY: "synthetic-public-project-key" };

it("hosted recovery preserves enumeration protection without hiding configuration failures", async () => {
  for (const failure of ["EMAIL_NOT_FOUND", "USER_DISABLED"]) {
    const app = mountHostedAuth(auth, firestore, verifier, environment,
      async () => new Response(JSON.stringify({ error: { message: failure } }), { status: 400 }));
    const response = await request(app).post("/auth/recovery/request").send({ email: "synthetic@fitnep.test" }).expect(200);
    assert.deepEqual(response.body.data, { requested: true });
  }
  const app = mountHostedAuth(auth, firestore, verifier, environment,
    async () => new Response("{}", { status: 403 }));
  await request(app).post("/auth/recovery/request").send({ email: "synthetic@fitnep.test" }).expect(503);
});
it("reset verification and confirmation delegate the single-use code to Firebase HTTPS", async () => {
  const app = mountHostedAuth(auth, firestore, verifier, environment, async (url, init) => {
    assert(String(url).startsWith("https://identitytoolkit.googleapis.com/v1/accounts:resetPassword"));
    const body = JSON.parse(init?.body as string);
    assert.equal(body.oobCode, "synthetic-reset-code");
    return new Response(JSON.stringify({ email: "synthetic@fitnep.test" }), { status: 200 });
  });
  const verified = await request(app).post("/auth/recovery/verify").send({ code: "synthetic-reset-code" }).expect(200);
  assert.equal(verified.body.data.email, "synthetic@fitnep.test");
  const confirmed = await request(app).post("/auth/recovery/confirm").send({ code: "synthetic-reset-code", password: "SyntheticPassword!123" }).expect(200);
  assert.deepEqual(confirmed.body.data, { confirmed: true });
});
it("expired reset codes and unsupported payloads cannot succeed or leak upstream details", async () => {
  const app = mountHostedAuth(auth, firestore, verifier, environment,
    async () => new Response(JSON.stringify({ error: { message: "EXPIRED_OOB_CODE" } }), { status: 400 }));
  const response = await request(app).post("/auth/recovery/verify").send({ code: "expired-synthetic-code" }).expect(404);
  assert(!JSON.stringify(response.body).includes("expired-synthetic-code"));
  await request(app).post("/auth/recovery/request").send({ email: "a@fitnep.test", role: "admin" }).expect(400);
  await request(app).post("/auth/signup/otp/send").send({ uid: "someone-else" }).expect(401);
});
it("missing recovery configuration rejects requests without contacting any service", async () => {
  const app = mountHostedAuth(auth, firestore, verifier, {}, async () => assert.fail("must not contact live services"));
  await request(app).post("/auth/recovery/request").send({ email: "synthetic@fitnep.test" }).expect(503);
});
