const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { applicationDefault, initializeApp } = require('firebase-admin/app');

// Reuse the operator's existing CLI login; never store credentials in the app.
module.exports = async function localFirebase(projectId) {
  const cliRoot = path.join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib');
  const cliAuth = require(path.join(cliRoot, 'auth.js'));
  const cliApi = require(path.join(cliRoot, 'api.js'));
  const account = cliAuth.getGlobalDefaultAccount();
  await require(path.join(cliRoot, 'requireAuth.js')).requireAuth({ project: projectId, ...account });
  if (!account?.tokens?.refresh_token) throw new Error('Sign in with the Firebase CLI first.');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'fitnep-live-'));
  const file = path.join(directory, 'credentials.json');
  fs.writeFileSync(file, JSON.stringify({
    type: 'authorized_user', client_id: cliApi.clientId(), client_secret: cliApi.clientSecret(),
    refresh_token: account.tokens.refresh_token,
  }), { mode: 0o600 });
  process.once('exit', () => { fs.unlinkSync(file); fs.rmdirSync(directory); });
  process.env.GOOGLE_APPLICATION_CREDENTIALS = file;
  return initializeApp({ projectId, credential: applicationDefault() });
};
