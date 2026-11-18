const test = require('node:test');
const assert = require('node:assert/strict');
const { requireValidSession } = require('../src/session.cjs');

const request = {
  auth: { uid: 'client' },
  rawRequest: { headers: { authorization: 'Bearer old-id-token' } },
};

test('valid session checks revocation and returns only the verified identity', async () => {
  const verified = await requireValidSession(request, {
    verifyIdToken: async (token, checkRevoked) => {
      assert.equal(token, 'old-id-token');
      assert.equal(checkRevoked, true);
      return { uid: 'client' };
    },
  });
  assert.equal(verified.uid, 'client');
});

test('both old sessions, disabled accounts and expired tokens are denied', async () => {
  for (const code of ['auth/id-token-revoked', 'auth/user-disabled', 'auth/id-token-expired']) {
    for (const token of ['session-one', 'session-two']) {
      await assert.rejects(requireValidSession({
        ...request, rawRequest: { headers: { authorization: `Bearer ${token}` } },
      }, {
        verifyIdToken: async () => { throw Object.assign(new Error(), { code }); },
      }), { code: 'unauthenticated' });
    }
  }
});

test('missing identity and malformed headers are denied before verification', async () => {
  const auth = { verifyIdToken: () => assert.fail('must not verify malformed input') };
  for (const input of [
    { rawRequest: request.rawRequest },
    { auth: request.auth },
    { ...request, rawRequest: { headers: { authorization: 'Basic token' } } },
    { ...request, rawRequest: { headers: { authorization: ['Bearer token'] } } },
    { ...request, rawRequest: { headers: { authorization: 'Bearer a b' } } },
  ]) {
    await assert.rejects(requireValidSession(input, auth), { code: 'unauthenticated' });
  }
});

test('mismatched identity is denied and verifier outage never grants access', async () => {
  await assert.rejects(requireValidSession(request, {
    verifyIdToken: async () => ({ uid: 'another-client' }),
  }), { code: 'unauthenticated' });
  await assert.rejects(requireValidSession(request, {
    verifyIdToken: async () => { throw new Error('service offline'); },
  }), { code: 'unavailable' });
});
