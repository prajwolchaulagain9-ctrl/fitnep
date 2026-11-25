// Same API and cloud Firestore as Render; development apps discover localhost.
const path = require('node:path');
const fs = require('node:fs');
const { parseEnv } = require('node:util');
const { execFileSync } = require('node:child_process');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { createFitnepDependencies } = require('../lib/api_factory');
const { createNotificationApp } = require('../lib/http_app');
const { mountHostedAuth } = require('../lib/hosted_auth');
const { FirestorePlatformSessionService } = require('../lib/platform_sessions');

const workspace = path.resolve(__dirname, '../..');
const project = 'fitnep-88908';
for (const name of ['.env.local', '.secret.local']) {
  const file = path.resolve(__dirname, '..', name);
  if (fs.existsSync(file)) Object.assign(process.env, parseEnv(fs.readFileSync(file, 'utf8')));
}
if (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('This runner uses live Firebase; remove emulator variables.');
}

(async () => {
  const firebase = await require('./local-firebase.cjs')(project);
  const auth = getAuth(firebase);
  const firestore = getFirestore(firebase);
  const dependencies = createFitnepDependencies(auth, firestore);
  const buildSha = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: workspace, encoding: 'utf8', windowsHide: true }).trim();
  const app = mountHostedAuth(auth, firestore, dependencies.authVerifier, process.env);
  // Use the configured Brevo delivery on Render when local secrets are absent.
  if (!process.env.BREVO_API_KEY) {
    const express = require('express');
    const proxy = express();
    proxy.use(express.json({ limit: '8kb' }));
    proxy.post(['/auth/signup/otp/send', '/auth/signup/otp/verify'], async (request, response) => {
      try {
        const result = await fetch('https://fitnep-api.onrender.com' + request.path, {
          method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: request.header('Authorization') || '' },
          body: JSON.stringify(request.body), signal: AbortSignal.timeout(60_000),
        });
        response.status(result.status).type('json').send(await result.text());
      } catch { response.status(503).json({ code: 'unavailable' }); }
    });
    proxy.use(app);
    start(proxy);
  } else start(app);

  function start(serverApp) {
    serverApp.use(createNotificationApp({
      ...dependencies,
      platformSessions: new FirestorePlatformSessionService(firestore, dependencies.auditWriter, 900),
      manualVerificationEnabled: false,
      health: { buildSha, checkReady: async () => { await firestore.doc('_runtime/health').get(); } },
    }));
    const server = serverApp.listen(3300, '127.0.0.1', () => console.log('FitNEP live Firebase API: http://127.0.0.1:3300'));
    server.on('error', error => { console.error('Local API could not start:', error.code); process.exitCode = 1; });
  }
})().catch(error => { console.error('Local API startup failed:', error.code || error.message); process.exitCode = 1; });
