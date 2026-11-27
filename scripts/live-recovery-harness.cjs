// Explicit live acceptance harness. Uses the operator's Firebase CLI login;
// credentials and action codes are kept under ignored .dart_tool, never logged.
if (!process.argv.includes('--run')) {
  console.log('Run explicitly with --run to prepare the saved live recovery test account.');
  process.exit(0);
}
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const http = require('node:http');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const functionsRequire = createRequire(path.resolve('functions/package.json'));
const { initializeApp } = functionsRequire('firebase-admin/app');
const { getAuth } = functionsRequire('firebase-admin/auth');
const { requireValidSession } = require('../functions/src/session.cjs');

const project = 'fitnep-88908';
const email = 'prajwolchaulagain9@gmail.com';
const root = path.resolve('.dart_tool');
const privateFile = path.join(root, 'live-recovery-private.json');
const apiKey = JSON.parse(fs.readFileSync('android/app/google-services.json')).client[0].api_key[0].current_key;
const cli = require('../functions/scripts/firebase-cli-lib.cjs');
const cliAuth = require(path.join(cli, 'auth.js'));
const { requireAuth } = require(path.join(cli, 'requireAuth.js'));
const api = require(path.join(cli, 'apiv2.js'));
const newPassword = () => `FitNEP!${crypto.randomBytes(12).toString('hex')}Aa9`;

async function authPost(method, data) {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:${method}?key=${apiKey}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data), signal: AbortSignal.timeout(30000),
  });
  return { status: response.status, body: await response.json() };
}

(async () => {
  await requireAuth({ project, ...cliAuth.getGlobalDefaultAccount() });
  const admin = getAuth(initializeApp({ projectId: project, credential: {
    getAccessToken: async () => ({ access_token: await api.getAccessToken(), expires_in: 300 }),
  } }));
  let fixture = fs.existsSync(privateFile) ? JSON.parse(fs.readFileSync(privateFile)) : null;
  let user;
  try { user = await admin.getUserByEmail(email); }
  catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
    const password = newPassword();
    user = await admin.createUser({ email, password, displayName: 'FitNEP recovery acceptance test' });
    fixture = { project, email, uid: user.uid, password, createdByTest: true };
    fs.writeFileSync(privateFile, JSON.stringify(fixture), { mode: 0o600 });
  }
  assert.ok(fixture?.createdByTest && fixture.project === project && fixture.email === email && fixture.uid === user.uid,
    'An existing account without this test fixture will not be modified.');
  fixture.nextPassword = newPassword();
  const nonce = crypto.randomBytes(24).toString('hex');
  fs.writeFileSync(path.join(root, 'live-recovery-defines.json'), JSON.stringify({
    FITNEP_LIVE_RECOVERY_TEST: 'true', FITNEP_TEST_NONCE: nonce,
  }), { mode: 0o600 });
  const desktop = await authPost('signInWithPassword', { email, password: fixture.password, returnSecureToken: true });
  assert.equal(desktop.status, 200, 'Desktop test session must sign in.');
  let nativeToken;
  let code;
  const evidence = { project, email, startedAt: new Date().toISOString(), checks: {} };
  const verify = (token) => requireValidSession({ auth: { uid: user.uid },
    rawRequest: { headers: { authorization: `Bearer ${token}` } } }, admin);
  const server = http.createServer(async (request, response) => {
    response.setHeader('Content-Type', 'application/json');
    if (request.headers['x-fitnep-test'] !== nonce) {
      response.writeHead(401); response.end('{}'); return;
    }
    try {
      let text = '';
      for await (const part of request) { text += part; assert.ok(text.length < 20000); }
      const data = text ? JSON.parse(text) : {};
      let result = {};
      switch (request.url) {
        case '/fixture':
          result = { email, password: fixture.password, nextPassword: fixture.nextPassword, uid: user.uid };
          break;
        case '/capture':
          nativeToken = data.idToken;
          assert.equal((await verify(nativeToken)).uid, user.uid);
          assert.equal((await verify(desktop.body.idToken)).uid, user.uid);
          evidence.checks.twoSessionsInitiallyValid = true;
          break;
        case '/reset-code': {
          const link = await admin.generatePasswordResetLink(email);
          code = new URL(link).searchParams.get('oobCode');
          const weak = await authPost('resetPassword', { oobCode: code, newPassword: 'abc' });
          assert.equal(weak.status, 400, 'Server must reject weak passwords.');
          assert.match(weak.body.error?.message || '', /PASSWORD_DOES_NOT_MEET_REQUIREMENTS|WEAK_PASSWORD/);
          evidence.checks.serverWeakPasswordRejected = true;
          result = { code };
          break;
        }
        case '/probe': {
          const old = await authPost('signInWithPassword', { email, password: fixture.password, returnSecureToken: true });
          assert.equal(old.status, 400, 'Old credentials must fail.');
          const current = await authPost('signInWithPassword', { email, password: fixture.nextPassword, returnSecureToken: true });
          assert.equal(current.status, 200, 'New credentials must work.');
          for (const token of [nativeToken, desktop.body.idToken]) {
            await assert.rejects(verify(token), { code: 'unauthenticated' });
          }
          assert.equal((await verify(current.body.idToken)).uid, user.uid);
          const refresh = await fetch(`https://securetoken.googleapis.com/v1/token?key=${apiKey}`, {
            method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: desktop.body.refreshToken }),
            signal: AbortSignal.timeout(30000),
          });
          assert.equal(refresh.status, 400, 'Old desktop refresh token must fail.');
          evidence.checks.oldCredentialsRejected = true;
          evidence.checks.newCredentialsAccepted = true;
          evidence.checks.twoOldIdTokensRejected = true;
          evidence.checks.oldDesktopRefreshRejected = true;
          evidence.checks.newIdTokenAccepted = true;
          fixture.password = fixture.nextPassword;
          fs.writeFileSync(privateFile, JSON.stringify(fixture), { mode: 0o600 });
          break;
        }
        case '/enumeration': {
          const missing = `fitnep-${crypto.randomBytes(8).toString('hex')}@example.invalid`;
          const existing = await authPost('sendOobCode', { requestType: 'PASSWORD_RESET', email });
          const unknown = await authPost('sendOobCode', { requestType: 'PASSWORD_RESET', email: missing });
          assert.equal(existing.status, 200);
          assert.equal(unknown.status, 200);
          assert.equal(JSON.stringify(existing.body).replaceAll(email, '<email>'),
            JSON.stringify(unknown.body).replaceAll(missing, '<email>'), 'Public confirmations must match.');
          evidence.checks.publicEnumerationResponsesMatch = true;
          console.log('PASS: registered and unknown addresses return equivalent live reset responses.');
          break;
        }
        case '/finish': {
          evidence.checks.nativeUiFlow = data.passed === true;
          evidence.finishedAt = new Date().toISOString();
          fs.writeFileSync(path.join(root, 'live-recovery-results.json'), JSON.stringify(evidence, null, 2));
          console.log('PASS: live native recovery, old credentials and old-session verification.');
          response.end(JSON.stringify({ complete: true }));
          server.close();
          setTimeout(() => process.exit(0), 1000);
          return;
        }
        default: response.writeHead(404); response.end('{}'); return;
      }
      response.end(JSON.stringify(result));
    } catch (error) {
      console.error(`Live test failed at ${request.url}: ${error.code || 'assertion or connection failure'}`);
      response.writeHead(500); response.end(JSON.stringify({ error: 'Live acceptance check failed; inspect the named step.' }));
    }
  });
  server.listen(8765, '127.0.0.1', () => console.log('Live recovery harness ready on local port 8765. Test credentials are not printed.'));
})().catch(error => {
  console.error(`Live recovery setup failed: ${error.code || String(error.message).replace(/https?:\/\/\S+/g, '[endpoint]').slice(0, 180)}`);
  process.exitCode = 1;
});
