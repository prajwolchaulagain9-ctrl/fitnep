// Trusted local OTP acceptance environment. Firebase Auth remains live; only the
// Functions runtime and OTP records are local. Never print credentials or codes.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const project = 'fitnep-88908';
const workspace = path.resolve(__dirname, '../..');
const cliRoot = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
const cliAuth = require(path.join(cliRoot, 'auth.js'));
const cliApi = require(path.join(cliRoot, 'api.js'));
const { requireAuth } = require(path.join(cliRoot, 'requireAuth.js'));

(async () => {
  const account = cliAuth.getGlobalDefaultAccount();
  await requireAuth({ project, ...account });
  if (!account?.tokens?.refresh_token) throw new Error('Sign in using the Firebase CLI first.');
  const privateDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'fitnep-otp-'));
  const privateFile = path.join(privateDirectory, 'local-admin-credentials.json');
  fs.writeFileSync(privateFile, JSON.stringify({
    type: 'authorized_user',
    client_id: cliApi.clientId(),
    client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  }), { mode: 0o600 });
  const cleanup = () => {
    if (fs.existsSync(privateFile)) fs.unlinkSync(privateFile);
    if (fs.existsSync(privateDirectory)) fs.rmdirSync(privateDirectory);
  };
  process.once('exit', cleanup);
  const jdk = process.env.JAVA_HOME || path.join(process.env.ProgramFiles, 'Android/Android Studio/jbr');
  const child = spawn(process.execPath, [path.join(cliRoot, 'bin/firebase.js'),
    'emulators:start', '--only', 'functions,firestore', '--project', project,
    '--config', 'firebase.json'], {
    cwd: workspace,
    env: { ...process.env, GOOGLE_APPLICATION_CREDENTIALS: privateFile, JAVA_HOME: jdk },
    stdio: 'inherit',
    windowsHide: true,
  });
  child.once('error', error => { console.error(error.message); cleanup(); process.exitCode = 1; });
  child.once('exit', code => { cleanup(); process.exitCode = code || 0; });
  process.once('SIGINT', () => child.kill('SIGINT'));
  process.once('SIGTERM', () => child.kill('SIGTERM'));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
