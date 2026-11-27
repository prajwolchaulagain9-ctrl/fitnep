// Opt-in timed expiry test. Creates and removes only its own temporary Auth user.
const resume = process.argv.includes('--resume');
if (!process.argv.includes('--run') && !resume) {
  console.log('Run with --run, or --resume to check and clean up an interrupted fixture. Results go to .dart_tool/live-expiry-results.json.');
  process.exit(0);
}
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { createRequire } = require('node:module');
const assert = require('node:assert/strict');
const functionsRequire = createRequire(path.resolve('functions/package.json'));
const { initializeApp } = functionsRequire('firebase-admin/app');
const { getAuth } = functionsRequire('firebase-admin/auth');
const cli = require('../functions/scripts/firebase-cli-lib.cjs');
const cliAuth = require(path.join(cli, 'auth.js'));
const { requireAuth } = require(path.join(cli, 'requireAuth.js'));
const api = require(path.join(cli, 'apiv2.js'));
const project = 'fitnep-88908';
const output = path.resolve('.dart_tool/live-expiry-results.json');
const privateOutput = path.resolve('.dart_tool/live-expiry-private.json');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

(async () => {
  await requireAuth({ project, ...cliAuth.getGlobalDefaultAccount() });
  const auth = getAuth(initializeApp({ projectId: project, credential: {
    getAccessToken: async () => ({ access_token: await api.getAccessToken(), expires_in: 300 }),
  } }));
  const apiKey = JSON.parse(fs.readFileSync('android/app/google-services.json')).client[0].api_key[0].current_key;
  const fixture = resume ? JSON.parse(fs.readFileSync(privateOutput)) : null;
  if (resume) assert.equal(fixture.project, project);
  const email = resume ? fixture.email : `prajwolchaulagain9+fitnep-expiry-${crypto.randomBytes(6).toString('hex')}@gmail.com`;
  const user = resume ? await auth.getUser(fixture.uid) : await auth.createUser({ email, password: `Expiry!Aa9${crypto.randomBytes(16).toString('hex')}`,
    displayName: 'Temporary FitNEP reset expiry test' });
  assert.equal(user.email, email);
  assert.equal(user.displayName, 'Temporary FitNEP reset expiry test');
  const evidence = resume ? JSON.parse(fs.readFileSync(output)) : { project, status: 'starting', checks: 0, temporaryUserRemoved: false };
  assert.equal(evidence.project, project);
  const save = () => fs.writeFileSync(output, JSON.stringify(evidence, null, 2));
  try {
    const link = resume ? null : await auth.generatePasswordResetLink(email);
    const code = resume ? fixture.code : new URL(link).searchParams.get('oobCode');
    const started = resume ? Date.parse(evidence.issuedAt) : Date.now();
    assert.ok(Number.isFinite(started));
    evidence.issuedAt = new Date(started).toISOString();
    evidence.status = 'waiting-for-provider-expiry';
    if (!resume) fs.writeFileSync(privateOutput, JSON.stringify({ project, uid: user.uid, email, code }), { mode: 0o600 });
    console.log('Timed live expiry check started. A separate temporary user isolates it from phone resets; no email is sent for this check.');
    const pollingStarted = Date.now();
    do {
      try {
        const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:resetPassword?key=${apiKey}`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ oobCode: code }), signal: AbortSignal.timeout(20000),
        });
        const body = await response.json();
        evidence.checks++;
        evidence.lastCheckedAt = new Date().toISOString();
        evidence.elapsedSeconds = Math.floor((Date.now() - started) / 1000);
        if (response.status === 200) {
          evidence.initiallyValid = true;
        } else {
          const error = body.error?.message || '';
          if (error.includes('EXPIRED_OOB_CODE')) {
            assert.ok(evidence.initiallyValid);
            evidence.status = 'expired';
            evidence.providerError = 'EXPIRED_OOB_CODE';
            save();
            console.log(`PASS: Firebase returned EXPIRED_OOB_CODE for the unused reset code checked ${evidence.elapsedSeconds} seconds after issue.`);
            return;
          }
          if (error.includes('INVALID_OOB_CODE') || error.includes('USER_NOT_FOUND')) {
            throw Object.assign(new Error('Action code was rejected without an expiry-specific response.'), { fatal: true });
          }
          evidence.lastTransientStatus = response.status;
        }
        save();
      } catch (error) {
        if (error.fatal) throw error;
        evidence.lastTransientStatus = 'connection-error';
        save();
      }
      if (resume) break;
      await delay(60000);
    } while (Date.now() - pollingStarted < 2 * 60 * 60 * 1000);
    throw new Error(resume ? 'Provider expiry was not confirmed at the resumed check.' : 'Provider expiry was not observed within the two-hour test limit.');
  } catch (error) {
    evidence.status = 'failed';
    evidence.reason = error.message;
    save();
    process.exitCode = 1;
  } finally {
    try {
      await auth.deleteUser(user.uid);
      evidence.temporaryUserRemoved = true;
      fs.rmSync(privateOutput, { force: true });
    } catch (_) { evidence.cleanupRequiresRetry = true; }
    save();
  }
})().catch(() => {
  console.error('Live expiry setup failed. No unrelated account was changed.');
  process.exitCode = 1;
});
