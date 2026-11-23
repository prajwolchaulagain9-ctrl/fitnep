const test = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { requireValidSession } = require('../src/session.cjs');

const project = process.env.GCLOUD_PROJECT;
assert.ok(project?.startsWith('demo-'), 'Use a demo project; never run these tests against live Auth.');
assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'Run using firebase emulators:exec.');
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Include the Firestore emulator.');
const authHost = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const functionsHost = process.env.FITNEP_FUNCTIONS_EMULATOR_HOST ?? '127.0.0.1:5001';
assert.match(functionsHost, /^(127\.0\.0\.1|localhost):\d+$/);
const auth = getAuth(initializeApp({ projectId: project }, 'fitnep-recovery-tests'));

async function authPost(method, body) {
  const response = await fetch(
    `${authHost}/identitytoolkit.googleapis.com/v1/accounts:${method}?key=demo-key`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) },
  );
  return { status: response.status, body: await response.json() };
}

function session(idToken, uid) {
  return { auth: { uid }, rawRequest: { headers: { authorization: `Bearer ${idToken}` } } };
}

test('real Auth reset is single-use, changes credentials and denies both old sessions', async () => {
  const email = `recovery-${Date.now()}@example.test`;
  const oldPassword = 'Previous!123';
  const newPassword = 'Updated!456';
  const created = await authPost('signUp', { email, password: oldPassword, returnSecureToken: true });
  assert.equal(created.status, 200);
  const uid = created.body.localId;
  try {
    const second = await authPost('signInWithPassword', { email, password: oldPassword, returnSecureToken: true });
    assert.equal(second.status, 200);
    for (const login of [created, second]) {
      const verified = await requireValidSession(session(login.body.idToken, uid), auth);
      assert.equal(verified.uid, uid);
    }
    const sent = await authPost('sendOobCode', { requestType: 'PASSWORD_RESET', email });
    assert.equal(sent.status, 200);
    const codesResponse = await fetch(`${authHost}/emulator/v1/projects/${project}/oobCodes`);
    const codes = await codesResponse.json();
    const code = codes.oobCodes.find((entry) => entry.email === email && entry.requestType === 'PASSWORD_RESET')?.oobCode;
    assert.ok(code, 'Emulator should contain the delivered reset action code.');

    const verified = await authPost('resetPassword', { oobCode: code });
    assert.equal(verified.status, 200);
    const weak = await authPost('resetPassword', { oobCode: code, newPassword: 'abc' });
    assert.equal(weak.status, 400);

    // Auth timestamps use whole seconds. Cross the boundary before resetting.
    await new Promise((resolve) => setTimeout(resolve, 1200));
    const reset = await authPost('resetPassword', { oobCode: code, newPassword });
    assert.equal(reset.status, 200);
    const replay = await authPost('resetPassword', { oobCode: code, newPassword: 'Replayed!789' });
    assert.equal(replay.status, 400);
    const oldLogin = await authPost('signInWithPassword', { email, password: oldPassword, returnSecureToken: true });
    assert.equal(oldLogin.status, 400);
    const newLogin = await authPost('signInWithPassword', { email, password: newPassword, returnSecureToken: true });
    assert.equal(newLogin.status, 200);

    for (const login of [created, second]) {
      await assert.rejects(requireValidSession(session(login.body.idToken, uid), auth), { code: 'unauthenticated' });
    }
    const current = await requireValidSession(session(newLogin.body.idToken, uid), auth);
    assert.equal(current.uid, uid);

    const callable = await fetch(`http://${functionsHost}/${project}/us-central1/checkSession`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${created.body.idToken}` },
      body: JSON.stringify({ data: {} }),
    });
    assert.equal(callable.status, 401);
    const freshCallable = await fetch(`http://${functionsHost}/${project}/us-central1/checkSession`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${newLogin.body.idToken}` },
      body: JSON.stringify({ data: {} }),
    });
    assert.equal(freshCallable.status, 200);

    // Direct Firestore is intentionally closed for the current Functions-only
    // protected access contract, including new sessions. Package rules follow US 9.
    const documentUrl = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${project}/databases/(default)/documents/users/${uid}`;
    for (const token of [created.body.idToken, second.body.idToken, newLogin.body.idToken]) {
      const read = await fetch(documentUrl, { headers: { Authorization: `Bearer ${token}` } });
      assert.equal(read.status, 403);
      const write = await fetch(documentUrl, {
        method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ fields: { role: { stringValue: 'admin' } } }),
      });
      assert.equal(write.status, 403);
    }
  } finally {
    await auth.deleteUser(uid);
  }
});
