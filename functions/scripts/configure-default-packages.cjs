const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { deleteApp } = require('firebase-admin/app');
const { FirestorePackageRepository } = require('../lib/firestore_package_repository');
const { PackageService } = require('../lib/package_service');

// Explicit operator setup; this never runs automatically on server startup.
const defaults = [
  { id: 'pkg_1795454194021389_cnx9lz', name: 'Basic', durationMonths: 1, price: 2500,
    featureDescription: 'Personalized nutrition guidance\nWeekly check-ins\nHealthy meal planning tips',
    previous: { name: 'basic', durationMonths: 2, price: 250, featureDescription: 'jxhbxujx' } },
  { id: 'fitnep-default-standard-v1', name: 'Standard', durationMonths: 2, price: 4500,
    featureDescription: 'Personalized nutrition and activity guidance\nProgress reviews\nCare team support' },
  { id: 'pkg_1795455195356329_54kiku', name: 'Premium', durationMonths: 3, price: 8000,
    featureDescription: 'Personalized nutrition and fitness coaching\nWeekly progress reviews\nPriority care team support',
    previous: { name: 'premium', durationMonths: 12, price: 25000000, featureDescription: 'everything' } },
];
const fields = ['name', 'durationMonths', 'price', 'featureDescription'];
const values = data => ({ name: data.name, durationMonths: data.duration_months, price: data.price, featureDescription: data.feature_description });
const matches = (left, right) => fields.every(key => left[key] === right[key]);
const digest = data => crypto.createHash('sha256').update(JSON.stringify(data)).digest('hex');

async function main() {
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('Default catalogue setup requires the owned live project.');
  }
  const app = await require('./local-firebase.cjs')('fitnep-88908');
  try {
    const auth = getAuth(app), db = getFirestore(app);
    const cliAuth = require(path.join(require('./firebase-cli-lib.cjs'), 'auth.js'));
    const email = cliAuth.getGlobalDefaultAccount()?.user?.email;
    if (!email) throw new Error('A signed-in operator is required.');
    const identity = await auth.getUserByEmail(email);
    const account = (await db.doc(`users/${identity.uid}`).get()).data();
    assert(account?.role === 'admin' && account.account_status === 'active' && !identity.disabled,
      'The signed-in operator must be an active FitNEP administrator.');
    const actor = { uid: identity.uid, role: 'admin', displayName: account.full_name || identity.displayName || identity.uid };
    const catalogue = await db.collection('packages').get();
    const selected = new Map(catalogue.docs.map(doc => [doc.id, doc]));
    for (const item of defaults) {
      const existing = selected.get(item.id);
      if (item.previous) assert(existing, `The inspected temporary ${item.name} package is missing.`);
      if (existing) assert(matches(values(existing.data()), item) || (item.previous && matches(values(existing.data()), item.previous)),
        `The ${item.name} package changed since inspection; review it before replacing it.`);
    }
    console.log(JSON.stringify({ apply: process.argv.includes('--apply'), defaults: defaults.map(({ name, durationMonths, price, featureDescription }) =>
      ({ name, durationMonths, priceNpr: price, features: featureDescription.split('\n') })) }, null, 2));
    if (!process.argv.includes('--apply')) return;

    const memberships = await db.collection('package_memberships').get();
    const beforeMemberships = new Map(memberships.docs.map(doc => [doc.id, digest(doc.data())]));
    const backupDirectory = path.resolve(__dirname, '../../.dart_tool/default-packages');
    fs.mkdirSync(backupDirectory, { recursive: true });
    const backupPath = path.join(backupDirectory, `catalogue-before-${Date.now()}.json`);
    fs.writeFileSync(backupPath, JSON.stringify(catalogue.docs.map(doc => ({ id: doc.id, ...doc.data() })), null, 2));

    const service = new PackageService(new FirestorePackageRepository(db));
    for (const item of defaults) {
      const input = Object.fromEntries(fields.map(key => [key, item[key]]));
      if (selected.has(item.id)) {
        await service.update(actor, item.id, input);
        await service.setActiveStatus(actor, item.id, true);
      } else await service.create(actor, { ...input, requestId: item.id });
    }
    const active = await service.list();
    for (const item of defaults) {
      const saved = active.find(record => record.id === item.id);
      assert(saved && matches(saved, item), `The ${item.name} package did not match the configured default.`);
    }
    const afterMemberships = await db.collection('package_memberships').get();
    assert.equal(afterMemberships.size, beforeMemberships.size, 'Membership count changed during catalogue setup.');
    for (const doc of afterMemberships.docs) assert.equal(digest(doc.data()), beforeMemberships.get(doc.id), 'An existing membership changed.');
    console.log(JSON.stringify({ configured: true, activePackages: active.map(({ name, durationMonths, price }) => ({ name, durationMonths, priceNpr: price })),
      membershipSnapshotsPreserved: afterMemberships.size, packageHistoryRecorded: true }));
  } finally { await deleteApp(app); }
}
main().catch(error => { console.error('Default package setup failed:', error.code || error.message); process.exitCode = 1; });
