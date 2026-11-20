import assert from "node:assert/strict";
import { it } from "node:test";
import { DecodedIdToken } from "firebase-admin/auth";
import { AuthenticationError, FirebaseAuthVerifier } from "../src/auth";

function verifier(claims: Record<string, unknown>) {
  return new FirebaseAuthVerifier({
    verifyIdToken: async (token, checkRevoked) => {
      assert.equal(token, "signed-token");
      assert.equal(checkRevoked, true);
      return { uid: "client-a", ...claims } as DecodedIdToken;
    },
  });
}

it("a verified account without an assigned role receives client access", async () => {
  assert.deepEqual(await verifier({ email_verified: true }).verifyIdToken("signed-token"), {
    uid: "client-a", role: "client",
  });
});

it("assigned roles are preserved and normalized", async () => {
  for (const role of ["admin", "dietitian", "client"]) {
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
      throw new Error("auth/id-token-revoked");
    },
  });
  await assert.rejects(auth.verifyIdToken("revoked-token"),
    error => error instanceof AuthenticationError && error.statusCode === 401);
});
