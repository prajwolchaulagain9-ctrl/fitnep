import assert from "node:assert/strict";
import { it } from "node:test";
import { DecodedIdToken, UserRecord } from "firebase-admin/auth";
import { AuthenticationError, FirebaseAuthVerifier } from "../src/auth";

function verifier(claims: Record<string, unknown>, currentClaims = claims) {
  return new FirebaseAuthVerifier({
    verifyIdToken: async (token, checkRevoked) => {
      assert.equal(token, "signed-token");
      assert.equal(checkRevoked, true);
      return { uid: "client-a", auth_time: 1700000000, ...claims } as DecodedIdToken;
    },
    getUser: async uid => {
      assert.equal(uid, "client-a");
      return {
        uid, disabled: currentClaims.disabled === true,
        emailVerified: currentClaims.email_verified === true,
        customClaims: currentClaims,
      } as UserRecord;
    },
  });
}

it("a verified account without an assigned role receives client access", async () => {
  assert.deepEqual(await verifier({ email_verified: true }).verifyIdToken("signed-token"), {
    uid: "client-a", role: "client",
    roleVersion: 0, authTime: 1700000000, emailVerified: true,
    mustChangePassword: false, permissions: { auditRead: false, paymentsVerify: false },
  });
});

it("assigned roles are preserved and normalized", async () => {
  for (const role of ["admin", "dietitian", "client", "staff"]) {
    const user = await verifier({ role: ` ${role.toUpperCase()} `, email_verified: true })
      .verifyIdToken("signed-token");
    assert.equal(user.role, role);
  }
});

it("unverified accounts and unsupported assigned roles are rejected", async () => {
  for (const claims of [{}, { email_verified: false }, { email_verified: "true" },
    ...[null, "owner", "", 1, ["admin"]].map(role => ({ role, email_verified: true }))]) {
    await assert.rejects(verifier(claims).verifyIdToken("signed-token"),
      error => error instanceof AuthenticationError && error.statusCode === 403);
  }
});

it("revoked or invalid Firebase tokens cannot receive default client access", async () => {
  const auth = new FirebaseAuthVerifier({
    verifyIdToken: async (_token, checkRevoked) => {
      assert.equal(checkRevoked, true);
      throw Object.assign(new Error("revoked"), { code: "auth/id-token-revoked" });
    },
    getUser: async () => assert.fail("must not read an account for a revoked token"),
  });
  await assert.rejects(auth.verifyIdToken("revoked-token"),
    error => error instanceof AuthenticationError && error.statusCode === 401);
});

it("current roles and permissions replace a captured privileged token on the next request", async () => {
  const user = await verifier(
    { role: "admin", role_version: 1, email_verified: true },
    { role: "staff", role_version: 2, email_verified: true, permissions: { audit_read: true } },
  ).verifyIdToken("signed-token");
  assert.equal(user.role, "staff");
  assert.equal(user.roleVersion, 2);
  assert.deepEqual(user.permissions, { auditRead: true, paymentsVerify: false });
});

it("deactivated accounts and malformed current role versions fail closed", async () => {
  for (const current of [{ disabled: true }, { role_version: -1 }, { role_version: "2" }]) {
    await assert.rejects(
      verifier({ role: "admin" }, { role: "client", email_verified: true, ...current })
        .verifyIdToken("signed-token"),
      error => error instanceof AuthenticationError && error.statusCode === 403,
    );
  }
});

it("an unavailable current-account lookup fails without treating the request as a successful login", async () => {
  const auth = new FirebaseAuthVerifier({
    verifyIdToken: async () => ({ uid: "client-a" }) as DecodedIdToken,
    getUser: async () => { throw new Error("upstream unavailable"); },
  });
  await assert.rejects(auth.verifyIdToken("signed-token"),
    error => error instanceof AuthenticationError && error.statusCode === 503);
});
