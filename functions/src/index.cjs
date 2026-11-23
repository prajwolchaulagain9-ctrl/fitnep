const { getApps, initializeApp } = require('firebase-admin/app');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { requireValidSession } = require('./session.cjs');

if (getApps().length === 0) initializeApp();

exports.checkSession = onCall(
  { region: 'us-central1', timeoutSeconds: 15, maxInstances: 5 },
  async (request) => {
    const token = await requireValidSession(request);
    const { FirestoreAccountService, FirestoreAuditStore } = require('../lib/account_service');
    const { PermissionDeniedError, requirePermission } = require('../lib/authorization_policy');
    let account;
    try {
      account = await new FirestoreAccountService(getFirestore(), getAuth()).current(token.uid);
      requirePermission(account.role, 'view_own_profile');
      if (account.account_status !== 'active') throw new PermissionDeniedError('The account is inactive.');
    } catch (error) {
      if (!(error instanceof PermissionDeniedError)) throw new HttpsError('unavailable', 'Account verification is unavailable.');
      await new FirestoreAuditStore(getFirestore()).denied({ uid: token.uid, role: account?.role ?? null,
        action: 'check_session', resource: 'session', reason: error.reason });
      throw new HttpsError('permission-denied', 'This account cannot access FitNEP. Contact support.');
    }
    return { uid: token.uid, role: account.role };
  },
);
