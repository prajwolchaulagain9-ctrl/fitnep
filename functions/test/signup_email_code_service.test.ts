import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";
import { HttpsError } from "firebase-functions/v2/https";

import { EmailCodeRecord, EmailCodeStore, EmailIdentity, SignupEmailCodeService } from "../src/signup_email_code_service";

class MemoryStore implements EmailCodeStore {
  records = new Map<string, EmailCodeRecord>();
  async mutate<T>(uid: string, change: (record: EmailCodeRecord | undefined) => {
    record: EmailCodeRecord | undefined;
    value: T;
  }): Promise<T> {
    const result = change(this.records.get(uid));
    if (result.record) this.records.set(uid, result.record);
    return result.value;
  }
}

const identity: EmailIdentity = { uid: "client-a", email: "client@example.com", emailVerified: false };
const errorCode = (code: string) => (error: unknown) => error instanceof HttpsError && error.code === code;

describe("signup email codes", () => {
  let store: MemoryStore;
  let service: SignupEmailCodeService;
  let time: number;
  let code: string;
  let verified: string[];
  let deliveryFails: boolean;
  let verificationFails: boolean;
  let deliveries: number;

  beforeEach(() => {
    store = new MemoryStore();
    time = 1_000_000;
    verified = [];
    deliveryFails = false;
    verificationFails = false;
    deliveries = 0;
    service = new SignupEmailCodeService(store, async (email, sentCode) => {
      assert.equal(email, identity.email);
      code = sentCode;
      deliveries++;
      if (deliveryFails) throw new Error("Private provider detail");
    }, async (account) => {
      if (verificationFails) throw new Error("Temporary Admin update failure");
      verified.push(account.uid);
    }, "test-secret-with-at-least-32-characters", () => time);
  });

  it("delivers six digits, stores a digest, and consumes the code once", async () => {
    assert.deepEqual(await service.send(identity), { resendAfterSeconds: 60 });
    assert.match(code, /^\d{6}$/);
    const stored = store.records.get(identity.uid)!;
    assert.notEqual(stored.digest, code);
    assert.equal(JSON.stringify(stored).includes(`\"${code}\"`), false);
    assert.deepEqual(await service.verify(identity, code), { verified: true });
    assert.deepEqual(verified, [identity.uid]);
    await assert.rejects(service.verify(identity, code), errorCode("invalid-argument"));
    assert.equal(verified.length, 1);
  });

  it("expires after ten minutes", async () => {
    await service.send(identity);
    time += 600_000;
    await assert.rejects(service.verify(identity, code), errorCode("deadline-exceeded"));
    assert.equal(verified.length, 0);
  });

  it("commits wrong attempts and rejects the correct code after five failures", async () => {
    await service.send(identity);
    const wrong = code === "000000" ? "000001" : "000000";
    for (let attempt = 0; attempt < 5; attempt++) {
      await assert.rejects(service.verify(identity, wrong), errorCode("invalid-argument"));
    }
    assert.equal(store.records.get(identity.uid)!.attempts, 5);
    await assert.rejects(service.verify(identity, code), errorCode("resource-exhausted"));
  });

  it("enforces resend cooldown and an hourly limit", async () => {
    await service.send(identity);
    await assert.rejects(service.send(identity, { resend: true }), errorCode("resource-exhausted"));
    for (let send = 1; send < 5; send++) {
      time += 60_000;
      await service.send(identity, { resend: true });
    }
    time += 60_000;
    await assert.rejects(service.send(identity, { resend: true }), errorCode("resource-exhausted"));
    time += 3_600_000;
    await service.send(identity, { resend: true });
  });

  it("binds the code to both UID and the current email", async () => {
    await service.send(identity);
    await assert.rejects(service.verify({ ...identity, uid: "client-b" }, code), errorCode("invalid-argument"));
    await assert.rejects(service.verify({ ...identity, email: "other@example.com" }, code), errorCode("invalid-argument"));
    assert.equal(verified.length, 0);
  });

  it("invalidates the old code on resend", async () => {
    await service.send(identity);
    const previousDigest = store.records.get(identity.uid)!.digest;
    time += 60_000;
    await service.send(identity, { resend: true });
    assert.notEqual(store.records.get(identity.uid)!.digest, previousDigest);
    await service.verify(identity, code);
  });

  it("prevents two concurrent requests from using the same code", async () => {
    await service.send(identity);
    const results = await Promise.allSettled([service.verify(identity, code), service.verify(identity, code)]);
    assert.equal(results.filter((result) => result.status === "fulfilled").length, 1);
    assert.equal(verified.length, 1);
  });

  it("invalidates a failed delivery without exposing provider details", async () => {
    deliveryFails = true;
    await assert.rejects(service.send(identity), errorCode("unavailable"));
    assert.equal(store.records.get(identity.uid)!.digest, "");
    await assert.rejects(service.verify(identity, code), errorCode("invalid-argument"));
    await assert.rejects(service.send(identity), errorCode("resource-exhausted"));
  });

  it("accepts an already verified retry without sending another email", async () => {
    const verifiedIdentity = { ...identity, emailVerified: true };
    assert.deepEqual(await service.verify(verifiedIdentity, "123456"), { verified: true });
    await assert.rejects(service.send(verifiedIdentity), errorCode("failed-precondition"));
  });

  it("rejects invalid code shapes before touching the challenge", async () => {
    for (const invalid of [null, 123456, "12345", "abcdef", "1234567"]) {
      await assert.rejects(service.verify(identity, invalid), errorCode("invalid-argument"));
    }
    assert.equal(store.records.size, 0);
  });

  it("resuming verification reuses the unexpired email without sending again", async () => {
    await service.send(identity);
    const digest = store.records.get(identity.uid)!.digest;
    time += 15_000;
    assert.deepEqual(await service.send(identity), { resendAfterSeconds: 45 });
    assert.equal(deliveries, 1);
    assert.equal(store.records.get(identity.uid)!.digest, digest);
    time += 60_000;
    assert.deepEqual(await service.send(identity), { resendAfterSeconds: 0 });
    assert.equal(deliveries, 1);
    await service.send(identity, { resend: true });
    assert.equal(deliveries, 2);
    assert.notEqual(store.records.get(identity.uid)!.digest, digest);
  });

  it("a failed Admin update preserves a correct code for a successful retry", async () => {
    await service.send(identity);
    verificationFails = true;
    await assert.rejects(service.verify(identity, code), errorCode("unavailable"));
    assert.equal(store.records.get(identity.uid)!.status, "sent");
    assert.equal(store.records.get(identity.uid)!.attempts, 0);
    verificationFails = false;
    assert.deepEqual(await service.verify(identity, code), { verified: true });
    assert.deepEqual(verified, [identity.uid]);
    assert.equal(store.records.get(identity.uid)!.digest, "");
  });
});
