import assert from "node:assert/strict";
import { it } from "node:test";
import request from "supertest";
import express from "express";
import { Auth } from "firebase-admin/auth";
import { Firestore } from "firebase-admin/firestore";
import { mountHostedAuth } from "../src/hosted_auth";
import { AuthenticationError } from "../src/auth";

const auth = {} as Auth; const firestore = {} as Firestore;
const verifier = { verifyIdToken: async () => { throw new AuthenticationError("No test identity."); } };
const environment = { FIREBASE_WEB_API_KEY: "synthetic-public-project-key" };

it("lets the application API parse multilingual intake answers above the auth body limit", async () => {
  const app = mountHostedAuth(auth, firestore, verifier, environment);
  app.post("/intakes/me/submit", express.json({ limit: "32kb" }), (req, res) => res.json(req.body));
  const answers = Object.fromEntries(["fitness_goals", "medical_history", "food_preferences"].map(
    field => [field, "क".repeat(1000)],
  ));
  await request(app).post("/intakes/me/submit").send({ answers }).expect(200, { answers });
  await request(app).post("/auth/signup/otp/send").send({ answers }).expect(413);
  await request(app).post("/auth/recovery/request").type("json").send("{").expect(400);
});

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

it("hosted signup sends a Brevo OTP for the authenticated email and verifies the received code", async () => {
  let record: Record<string, unknown> | undefined;
  let deliveredCode = "";
  let emailVerified = false;
  const database = {
    collection: () => ({ doc: () => ({}) }),
    runTransaction: async (change: (transaction: unknown) => unknown) => change({
      get: async () => ({ data: () => record }),
      set: (_reference: unknown, data: Record<string, unknown>) => { record = { ...data }; },
    }),
  } as unknown as Firestore;
  const identity = { uid: "otp-client", email: "signup@fitnep.test", disabled: false,
    providerData: [{ providerId: "password" }] };
  const nativeAuth = {
    getUser: async () => ({ ...identity, emailVerified }),
    updateUser: async (_uid: string, input: { email: string; emailVerified: boolean }) => {
      assert.equal(input.email, identity.email);
      emailVerified = input.emailVerified;
    },
  } as unknown as Auth;
  const verifier = { verifyIdToken: async () => ({ uid: identity.uid, role: "client" as const, emailVerified }) };
  const settings = { BREVO_API_KEY: "synthetic-key", BREVO_SENDER_EMAIL: "sender@fitnep.test", SIGNUP_OTP_HASH_SECRET: "synthetic".repeat(8) };
  const app = mountHostedAuth(nativeAuth, database, verifier, settings, async (_url, options) => {
    const mail = JSON.parse(options!.body as string);
    assert.equal(mail.to[0].email, identity.email);
    deliveredCode = mail.textContent.match(/\b\d{6}\b/)[0];
    return new Response(JSON.stringify({ messageId: "accepted-otp-mail" }), { status: 201 });
  });
  const sent = await request(app).post("/auth/signup/otp/send").set("Authorization", "Bearer synthetic-token").send({}).expect(200);
  assert.equal(sent.body.data.resendAfterSeconds, 60);
  assert.equal(record!.messageId, "accepted-otp-mail");
  assert(!JSON.stringify(sent.body).includes(deliveredCode));
  assert(!JSON.stringify(record).includes(deliveredCode));
  await request(app).post("/auth/signup/otp/verify").set("Authorization", "Bearer synthetic-token").send({ code: deliveredCode }).expect(200);
  assert.equal(emailVerified, true);
  assert.equal(record!.status, "consumed");
});
