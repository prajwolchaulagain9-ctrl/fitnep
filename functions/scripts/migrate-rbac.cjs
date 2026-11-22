// Uses trusted server credentials. Default is a read-only migration preview.
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { isUserRole } = require('../lib/domain');
const taskArgs = process.argv.slice(2);
const taskProject = taskArgs.find(arg => arg.startsWith('--project='))?.slice(10);
const taskApply = taskArgs.includes('--apply');
const taskAdminUid = taskArgs.find(arg => arg.startsWith('--bootstrap-admin='))?.slice(18);
if (!taskProject) throw new Error('Specify --project=<firebase-project-id>.');
initializeApp({ projectId: taskProject });
const auth = getAuth(); const db = getFirestore();
async function main() {
  let pageToken, candidates = 0, migrated = 0, invalid = 0;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const identity of page.users) {
      const ref = db.collection('users').doc(identity.uid);
      const snapshot = await ref.get(); const data = snapshot.data();
      const accessRef = db.collection('account_access').doc(identity.uid);
      const accessExists = (await accessRef.get()).exists;
      if (data && Object.hasOwn(data, 'role_revision') && !isUserRole(data.role)) {
        invalid++; console.error('Invalid authoritative role; operator review required for UID:', identity.uid); continue;
      }
      const role = data?.role ?? identity.customClaims?.role ?? 'client';
      if (!isUserRole(role)) {
        invalid++; console.error('Invalid role; operator review required for UID:', identity.uid); continue;
      }
      const needsMigration = !accessExists || !data || data.role !== role || !['active','inactive'].includes(data.account_status) ||
        !(data.created_at instanceof Timestamp) || !(data.updated_at instanceof Timestamp);
      if (!needsMigration) continue;
      candidates++;
      if (!taskApply) continue;
      await db.runTransaction(async transaction => {
        const current = (await transaction.get(ref)).data();
        if (current && Object.hasOwn(current, 'role_revision') && !isUserRole(current.role)) {
          throw new Error('Concurrent invalid authoritative role; migration stopped.');
        }
        const currentRole = current?.role ?? identity.customClaims?.role ?? 'client';
        if (!isUserRole(currentRole)) throw new Error('Concurrent invalid role; migration stopped.');
        transaction.set(ref, { ...(current ?? {}), role: currentRole,
          full_name: current?.full_name ?? identity.displayName ?? '', email: current?.email ?? identity.email ?? '',
          account_status: identity.disabled ? 'inactive' : current?.account_status === 'inactive' ? 'inactive' : 'active',
          role_revision: current?.role_revision ?? 0,
          created_at: current?.created_at instanceof Timestamp ? current.created_at : Timestamp.fromDate(new Date(identity.metadata.creationTime)),
          updated_at: FieldValue.serverTimestamp(),
        });
        transaction.set(accessRef, { revision: current?.role_revision ?? 0, updated_at: FieldValue.serverTimestamp() });
        transaction.create(db.collection('audit_logs').doc(), { user_id: 'server_operator', current_role: null,
          action: 'migrate_account_role', resource: 'users', record_id: identity.uid, result: 'ALLOWED',
          previous_role: current?.role ?? null, new_role: currentRole, timestamp: FieldValue.serverTimestamp() });
      }); migrated++;
    }
    pageToken = page.pageToken;
  } while (pageToken);
  if (taskAdminUid) {
    const identity = await auth.getUser(taskAdminUid);
    if (identity.disabled) throw new Error('Bootstrap requires an enabled Firebase account.');
    if (taskApply) {
      await db.runTransaction(async transaction => {
        const admins = await transaction.get(db.collection('users').where('role','==','admin').where('account_status','==','active').limit(1));
        if (!admins.empty) throw new Error('An active admin already exists. Use authenticated user management.');
        const ref = db.collection('users').doc(taskAdminUid);
        const current = (await transaction.get(ref)).data();
        if (!current || !isUserRole(current.role)) throw new Error('Migrate the bootstrap account first.');
        transaction.update(ref, { role: 'admin', account_status: 'active', role_revision: (current.role_revision ?? 0) + 1,
          updated_at: FieldValue.serverTimestamp() });
        transaction.set(db.collection('account_access').doc(taskAdminUid), {
          revision: (current.role_revision ?? 0) + 1, updated_at: FieldValue.serverTimestamp(),
        });
        transaction.create(db.collection('audit_logs').doc(), { user_id: 'server_operator', current_role: null,
          action: 'bootstrap_admin', resource: 'user_management', record_id: taskAdminUid, result: 'ALLOWED',
          previous_role: current.role, new_role: 'admin', timestamp: FieldValue.serverTimestamp() });
      });
    } else console.log('Bootstrap preview for UID:', taskAdminUid);
  }
  console.log(JSON.stringify({ mode: taskApply ? 'applied' : 'preview', candidates, migrated, invalid }));
  if (invalid) process.exitCode = 1;
}
main().catch(() => { console.error('RBAC migration stopped. Check credentials and the reported account IDs.'); process.exitCode = 1; });
