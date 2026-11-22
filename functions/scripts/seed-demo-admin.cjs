// Run explicitly: npm --prefix functions run seed:admin
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

if (!process.argv.includes('--run')) {
  console.log('Use npm --prefix functions run seed:admin to seed the demo admin.');
  process.exit(0);
}

const workspace = path.resolve(__dirname, '../..');
const config = JSON.parse(fs.readFileSync(path.join(workspace, 'android/app/google-services.json')));
const project = config.project_info.project_id;
const uid = 'fitnep-demo-admin';
const email = 'demo-admin@fitnep.test';
const credentialsFile = path.join(workspace, '.dart_tool/demo-admin.credentials.json');

async function main() {
  assert.ok(!process.env.FIREBASE_AUTH_EMULATOR_HOST, 'This seed targets the Firebase project used by the live app.');
  const cliRoot = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
  const cliAuth = require(path.join(cliRoot, 'auth.js'));
  const cliApi = require(path.join(cliRoot, 'apiv2.js'));
  const { requireAuth } = require(path.join(cliRoot, 'requireAuth.js'));
  await requireAuth({ project, ...cliAuth.getGlobalDefaultAccount() });
  const app = initializeApp({ projectId: project, credential: {
    getAccessToken: async () => ({ access_token: await cliApi.getAccessToken(), expires_in: 300 }),
  } });

  try {
    const auth = getAuth(app);
    let credentials = fs.existsSync(credentialsFile)
      ? JSON.parse(fs.readFileSync(credentialsFile)) : null;
    if (credentials) {
      assert.ok(credentials.project === project && credentials.uid === uid && credentials.email === email &&
        credentials.createdBySeed === true && typeof credentials.password === 'string', 'The saved seed must match this demo account.');
    }
    let user;
    try { user = await auth.getUser(uid); }
    catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
    }
    if (!user) {
      credentials ??= { project, uid, email, password: `FitNEP!${crypto.randomBytes(9).toString('base64url')}Aa9`, createdBySeed: true };
      fs.mkdirSync(path.dirname(credentialsFile), { recursive: true });
      // Save before the request so a retry keeps the same password after a lost response.
      fs.writeFileSync(credentialsFile, JSON.stringify(credentials, null, 2), { mode: 0o600 });
      user = await auth.createUser({ uid, email, password: credentials.password, emailVerified: true, displayName: 'Demo Admin' });
    }
    assert.ok(credentials && user.email === email, 'An existing account without the saved seed will not be changed.');
    assert.ok(!user.disabled, 'The seeded account is disabled.');
    if (!user.emailVerified) await auth.updateUser(uid, { emailVerified: true });
    await auth.setCustomUserClaims(uid, { ...user.customClaims, role: 'admin' });

    const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${config.client[0].api_key[0].current_key}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: credentials.password, returnSecureToken: true }),
      signal: AbortSignal.timeout(30000),
    });
    assert.equal(response.status, 200, 'The seeded credentials must sign in.');
    const session = await response.json();
    const token = await auth.verifyIdToken(session.idToken, true);
    assert.equal(token.uid, uid);
    assert.equal(token.role, 'admin');
    assert.equal(token.email_verified, true);
    console.log(JSON.stringify({ project, email, uid, role: token.role, emailVerified: true, credentialsFile,
      checks: ['password login', 'verified email', 'admin token', 'revocation check'] }, null, 2));
  } finally {
    await deleteApp(app);
  }
}

main().catch(error => {
  console.error(`Demo admin seed failed: ${error.code || 'setup/check failure'}. ${String(error.message).replace(/https?:\/\/\S+/g, '[endpoint]').slice(0, 180)}`);
  process.exitCode = 1;
});
