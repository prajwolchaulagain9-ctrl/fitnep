const { getApps, initializeApp } = require('firebase-admin/app');
const { onCall } = require('firebase-functions/v2/https');
const { requireValidSession } = require('./session.cjs');

if (getApps().length === 0) initializeApp();

exports.checkSession = onCall(
  { region: 'us-central1', timeoutSeconds: 15, maxInstances: 5 },
  async (request) => {
    const token = await requireValidSession(request);
    return { uid: token.uid };
  },
);
