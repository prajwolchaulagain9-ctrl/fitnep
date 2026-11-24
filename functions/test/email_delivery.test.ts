import assert from "node:assert/strict";
import { it } from "node:test";
import { Auth } from "firebase-admin/auth";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { BrevoMailer } from "../src/brevo_mailer";
import { GooglePasswordService } from "../src/google_password_service";
import { AuthenticatedUser } from "../src/domain";

it("Brevo requires provider acceptance and preserves safe configuration errors", async () => {
  const environment = { BREVO_API_KEY: "synthetic-key", BREVO_SENDER_EMAIL: "sender@fitnep.test" };
  const success = new BrevoMailer(environment, async (_url, options) => {
    const body = JSON.parse(options!.body as string);
    assert.equal(body.sender.email, environment.BREVO_SENDER_EMAIL);
    assert.equal(body.to[0].email, "recipient@fitnep.test");
    return new Response(JSON.stringify({ messageId: "synthetic-message" }), { status: 201 });
  });
  assert.equal(await success.send("recipient@fitnep.test", "OTP", "123456"), "synthetic-message");
  const rejected = new BrevoMailer(environment, async () => new Response('{"message":"private provider detail"}', { status: 401 }));
  await assert.rejects(rejected.send("recipient@fitnep.test", "OTP", "123456"), error => {
    assert(error instanceof HttpsError);
    assert.equal(error.code, "failed-precondition");
    assert(!JSON.stringify(error).includes("private provider detail"));
    return true;
  });
  await assert.rejects(new BrevoMailer(environment, async () => new Response("{}", { status: 201 }))
    .send("recipient@fitnep.test", "OTP", "123456"));
});

function fixture() {
  let now = 1_800_000_000_000;
  let claims: Record<string, unknown> = {};
  let providers = [{ providerId: "google.com" }];
  let password = "";
  let installs = 0;
  let revocations = 0;
  let deliveryFails = false;
  const mails: string[] = [];
  let stored: Record<string, unknown> | undefined;
  const reference = {
    get: async () => ({ data: () => stored && { ...stored } }),
    update: async (changes: Record<string, unknown>) => {
      for (const [key, value] of Object.entries(changes)) {
        if (value instanceof FieldValue && value.isEqual(FieldValue.delete())) delete stored![key];
        else stored![key] = value;
      }
    },
  };
  const db = { collection: () => ({ doc: () => reference }),
    runTransaction: async (action: (transaction: unknown) => unknown) => action({
      get: async () => reference.get(), set: (_reference: unknown, data: Record<string, unknown>) => { stored = { ...data }; },
    }),
  } as unknown as Firestore;
  const auth = {
    getUser: async () => ({ uid: "google-client", email: "client@fitnep.test", emailVerified: true, disabled: false,
      providerData: [...providers], customClaims: { ...claims } }),
    updateUser: async (_uid: string, changes: { password: string }) => { password = changes.password; installs++; providers = [{ providerId: "google.com" }, { providerId: "password" }]; },
    setCustomUserClaims: async (_uid: string, value: Record<string, unknown>) => { claims = { ...value }; },
    revokeRefreshTokens: async () => { revocations++; },
  } as unknown as Auth;
  const mailer = new BrevoMailer({ BREVO_API_KEY: "synthetic-key", BREVO_SENDER_EMAIL: "sender@fitnep.test" }, async (_url, options) => {
    const body = JSON.parse(options!.body as string);
    mails.push(body.textContent);
    return deliveryFails ? new Response("{}", { status: 503 })
      : new Response(JSON.stringify({ messageId: "synthetic-message" }), { status: 201 });
  });
  const actor: AuthenticatedUser = { uid: "google-client", role: "client", email: "client@fitnep.test", emailVerified: true,
    signInProvider: "google.com", authTime: now / 1000 };
  return { service: new GooglePasswordService(auth, db, mailer, "synthetic-secret".repeat(4), () => now), actor,
    state: () => ({ stored, claims, password, installs, revocations, mails }),
    setExistingPassword: () => { providers.push({ providerId: "password" }); password = "ExistingPassword!123"; },
    failDelivery: (value: boolean) => { deliveryFails = value; },
    advance: (milliseconds: number) => { now += milliseconds; actor.authTime = now / 1000; },
  };
}

it("Google setup emails a strong password once, removes encrypted mail data, and preserves existing passwords", async () => {
  const test = fixture();
  assert.deepEqual(await test.service.send(test.actor), { email_sent: true, credentials_updated: true });
  const state = test.state();
  assert(state.password.length >= 24);
  assert(state.mails[0]!.includes(state.password));
  assert(!JSON.stringify(state.stored ?? {}).includes(state.password));
  assert.equal(state.stored!.ciphertext, undefined);
  assert.equal(state.stored!.iv, undefined);
  await test.service.send(test.actor);
  assert.equal(test.state().installs, 1);
  assert.equal(test.state().mails.length, 1);
  const existing = fixture();
  existing.setExistingPassword();
  await existing.service.send(existing.actor);
  assert.equal(existing.state().password, "ExistingPassword!123");
  assert.equal(existing.state().installs, 0);
  assert.equal(existing.state().mails.length, 0);
});

it("failed email delivery retries the same installed password without replacing it", async () => {
  const test = fixture();
  test.failDelivery(true);
  await assert.rejects(test.service.send(test.actor));
  const password = test.state().password;
  assert(!JSON.stringify(test.state().stored ?? {}).includes(password));
  test.failDelivery(false);
  await test.service.send(test.actor);
  assert.equal(test.state().password, password);
  assert.equal(test.state().installs, 1);
  assert.equal(test.state().mails[0], test.state().mails[1]);
});

it("temporary passwords require recent email login, replacement and a bounded expiry", async () => {
  const test = fixture();
  await test.service.send(test.actor);
  const emailActor = { ...test.actor, signInProvider: "password", passwordAuthenticatedAt: test.actor.authTime, googleTemporaryPassword: true };
  await assert.rejects(test.service.change(emailActor, test.state().password));
  await assert.rejects(test.service.change({ ...test.actor, signInProvider: "custom" }, "NewPassword!123"));
  await test.service.change(emailActor, "NewPassword!123");
  assert.equal(test.state().password, "NewPassword!123");
  assert.equal(test.state().claims.googlePasswordSetupId, undefined);
  assert.equal(test.state().revocations, 1);
  assert.equal(test.state().stored!.status, "completed");
  const expired = fixture();
  await expired.service.send(expired.actor);
  expired.advance(86_400_001);
  await assert.rejects(expired.service.change({ ...expired.actor, signInProvider: "password", passwordAuthenticatedAt: expired.actor.authTime, googleTemporaryPassword: true }, "NewPassword!123"));
  const oldPassword = expired.state().password;
  await expired.service.send(expired.actor);
  assert.equal(expired.state().password, oldPassword);
  await expired.service.change({ ...expired.actor, googleTemporaryPassword: true }, "RecoveredPassword!123");
  assert.equal(expired.state().password, "RecoveredPassword!123");
});

it("unverified and non-Google sessions cannot install credentials or request mail", async () => {
  const test = fixture();
  await assert.rejects(test.service.send({ ...test.actor, emailVerified: false }));
  await assert.rejects(test.service.send({ ...test.actor, signInProvider: "password" }));
  await assert.rejects(test.service.send({ ...test.actor, email: "other@fitnep.test" }));
  assert.equal(test.state().installs, 0);
  assert.equal(test.state().mails.length, 0);
});
