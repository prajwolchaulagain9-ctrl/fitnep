import assert from "node:assert/strict";
import { it } from "node:test";
import { DecodedIdToken, UserRecord } from "firebase-admin/auth";
import { AuthenticationError, FirebaseAuthVerifier } from "../src/auth";
import { Account } from "../src/account_service";
import { PermissionDeniedError } from "../src/authorization_policy";
import { UserRole } from "../src/domain";

function verifier(role: UserRole, tokenClaims: Record<string, unknown> = {},
  current: Record<string, unknown> = {}, revision = 1) {
  return new FirebaseAuthVerifier({
    auth: {
      verifyIdToken: async (token, checkRevoked) => {
        assert.equal(token, "signed-token"); assert.equal(checkRevoked, true);
        return { uid: "client-a", auth_time: 1700000000, email_verified: true, ...tokenClaims } as DecodedIdToken;
      },
      getUser: async () => ({ uid: "client-a", disabled: current.disabled === true,
        emailVerified: true, email: "a@fitnep.test", customClaims: current }) as UserRecord,
    },
    current: async () => {
      if (current.invalid) throw new PermissionDeniedError("Invalid current account.");
      return { id: "client-a", role, role_revision: revision, account_status: "active" } as Account;
    },
  });
}
it("canonical accounts supply exactly one role; token claims cannot override it", async () => {
  for (const role of ["client", "staff", "dietitian", "admin"] as UserRole[]) {
    const user = await verifier(role, { role: "owner" }).verifyIdToken("signed-token");
    assert.equal(user.role, role); assert.equal(user.roleRevision, 1);
  }
});
it("captured admin claims cannot retain permissions after canonical demotion", async () => {
  const user = await verifier("staff", { role: "admin", role_version: 1 }, { role: "admin" }, 2).verifyIdToken("signed-token");
  assert.equal(user.roleVersion, 2);
  assert.deepEqual(user.permissions, { auditRead: false, paymentsVerify: false });
});
it("unverified identities can finish OTP but cannot claim email verification", async () => {
  const user = await verifier("client", { email_verified: false }).verifyIdToken("signed-token");
  assert.equal(user.emailVerified, false);
});
it("deactivated or malformed current accounts fail closed", async () => {
  for (const current of [{ disabled: true }, { invalid: true }]) {
    await assert.rejects(verifier("client", {}, current).verifyIdToken("signed-token"),
      error => error instanceof AuthenticationError && error.statusCode === 403);
  }
});
it("a changed staff credential marker rejects a captured token", async () => {
  await assert.rejects(verifier("staff", { staffRoleVersion: "old" }, { staffRoleVersion: "new" }).verifyIdToken("signed-token"),
    error => error instanceof AuthenticationError && error.statusCode === 401);
});
it("revoked tokens cannot reach the canonical account lookup", async () => {
  const auth = new FirebaseAuthVerifier({
    auth: { verifyIdToken: async () => { throw Object.assign(new Error("revoked"), { code: "auth/id-token-revoked" }); },
      getUser: async () => assert.fail("must not read account") },
    current: async () => assert.fail("must not provision after revocation"),
  });
  await assert.rejects(auth.verifyIdToken("captured"), error => error instanceof AuthenticationError && error.statusCode === 401);
});
it("unavailable account lookup cannot produce a successful login", async () => {
  const auth = new FirebaseAuthVerifier({
    auth: { verifyIdToken: async () => ({ uid: "client-a" }) as DecodedIdToken,
      getUser: async () => { throw new Error("unavailable"); } },
    current: async () => assert.fail("must not provision"),
  });
  await assert.rejects(auth.verifyIdToken("signed-token"), error => error instanceof AuthenticationError && error.statusCode === 503);
});
