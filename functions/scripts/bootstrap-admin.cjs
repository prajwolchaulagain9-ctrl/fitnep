const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { randomUUID } = require('node:crypto');
const { FirestoreAccountService, accountFrom } = require('../lib/account_service');
const { FirestoreAuditWriter } = require('../lib/audit');

// Trusted first-admin setup; never available as a public API or client action.
(async () => {
  const email = process.argv.find(arg => arg.startsWith('--email='))?.slice(8);
  if (!email) throw new Error('Specify --email=<existing Firebase account>.');
  const app = await require('./local-firebase.cjs')('fitnep-88908');
  const auth = getAuth(app);
  const db = getFirestore(app);
  const user = await auth.getUserByEmail(email);
  if (user.disabled || !user.emailVerified) throw new Error('An enabled, verified account is required.');
  if (!process.argv.includes('--apply')) {
    console.log('Verified existing account; run with --apply to assign the first Admin/CEO role.');
    return;
  }
  await new FirestoreAccountService(db, auth).provision(user);
  await db.runTransaction(async transaction => {
    const ref = db.collection('users').doc(user.uid);
    const current = accountFrom(user.uid, (await transaction.get(ref)).data());
    if (current.role === 'admin' && current.account_status === 'active') return;
    const admins = await transaction.get(db.collection('users').where('role', '==', 'admin').where('account_status', '==', 'active').limit(1));
    if (!admins.empty) throw new Error('An active admin exists. Use authenticated user management.');
    const revision = current.role_revision + 1;
    transaction.update(ref, { role: 'admin', account_status: 'active', role_revision: revision, updated_at: FieldValue.serverTimestamp() });
    transaction.set(db.collection('account_access').doc(user.uid), { revision, updated_at: FieldValue.serverTimestamp() });
    transaction.create(db.collection('audit_logs').doc(), {
      user_id: 'server_operator', current_role: null, action: 'bootstrap_admin', resource: 'user_management',
      record_id: user.uid, result: 'ALLOWED', previous_role: current.role, new_role: 'admin', timestamp: FieldValue.serverTimestamp(),
    });
    new FirestoreAuditWriter(db).appendInTransaction(transaction, {
      actor: { uid: user.uid, role: 'admin' }, action: 'account.role_changed', targetType: 'account',
      targetId: user.uid, outcome: 'succeeded', correlationId: randomUUID(),
    });
  });
  console.log('Admin/CEO role saved and verified in live Firestore.');
})().catch(error => { console.error('Admin setup failed:', error.code || error.message); process.exitCode = 1; });
