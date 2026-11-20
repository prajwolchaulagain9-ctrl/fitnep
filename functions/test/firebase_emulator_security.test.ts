import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import request from "supertest";

import { FirebaseAuthVerifier } from "../src/auth";
import { UserRole } from "../src/domain";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
import { FirestorePrivacyAcceptanceStore, PrivacyAcceptanceError, privacyPolicyVersion } from "../src/privacy_policy_acceptance";
import { FirestorePrivacyPreferencesRepository } from "../src/firestore_privacy_preferences_repository";
import { FirestorePrivateRecordsStore } from "../src/firestore_private_records_store";
import { FirestorePackageRepository } from "../src/firestore_package_repository";
import { FirestorePackageService } from "../src/package_membership_service";
import {
  addCalendarMonths,
  FirestorePurchaseRepository,
} from "../src/firestore_purchase_repository";
import { createNotificationApp } from "../src/http_app";
import { NotificationWorkflowService } from "../src/notification_service";

const projectId = "demo-fitnep";
const authEmulatorHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreEmulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const emulatorDescribe =
  authEmulatorHost === undefined || firestoreEmulatorHost === undefined
    ? describe.skip
    : describe;

emulatorDescribe("Firebase Auth and Firestore recipient isolation", () => {
  let firebaseApp: App;
  let auth: Auth;
  let firestore: Firestore;
  let repository: FirestoreNotificationRepository;
  let workflows: NotificationWorkflowService;
  let packageRepository: FirestorePackageRepository;
  let purchaseRepository: FirestorePurchaseRepository;
  let api: ReturnType<typeof createNotificationApp>;

  before(() => {
    firebaseApp = initializeApp({ projectId });
    auth = getAuth(firebaseApp);
    firestore = getFirestore(firebaseApp);
    repository = new FirestoreNotificationRepository(firestore);
    packageRepository = new FirestorePackageRepository(firestore);
    purchaseRepository = new FirestorePurchaseRepository(firestore);
    workflows = new NotificationWorkflowService(repository);
    const privacyPreferencesRepository = new FirestorePrivacyPreferencesRepository(firestore);
    api = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      packageRepository,
      purchaseRepository,
      packageService: new FirestorePackageService(firestore),
      privacyPreferencesRepository,
      privateRecordsStore: new FirestorePrivateRecordsStore(firestore, privacyPreferencesRepository),
    });
  });

  beforeEach(async () => {
    await Promise.all([clearAuth(), clearFirestore()]);
    await Promise.all([
      createAccount(auth, "client-a", "client-a@fitnep.test", "client"),
      createAccount(auth, "client-b", "client-b@fitnep.test", "client"),
      createAccount(
        auth,
        "dietitian-1",
        "dietitian@fitnep.test",
        "dietitian",
      ),
      createAccount(
        auth,
        "admin-1",
        "admin@fitnep.test",
        "admin",
        "FitNep CEO",
      ),
    ]);
  });

  after(async () => {
    await deleteApp(firebaseApp);
  });

  it("stores the server acceptance date once and requires confirmation for minors", async () => {
    const acceptanceStore = new FirestorePrivacyAcceptanceStore(firestore);
    const reference = firestore.collection("privacy_acceptances").doc("client-a");
    const form = {
      age: 17,
      privacy_policy_version: privacyPolicyVersion,
      privacy_policy_accepted: true,
    };
    await assert.rejects(acceptanceStore.recordForClient("client-a", form), PrivacyAcceptanceError);
    assert.equal((await reference.get()).exists, false);
    const confirmed = { ...form, guardian_consent_confirmed: true };
    await acceptanceStore.recordForClient("client-a", confirmed);
    const stored = await reference.get();
    assert.equal(stored.get("policy_version"), privacyPolicyVersion);
    assert(stored.get("accepted_at") instanceof Timestamp);
    assert(stored.get("guardian_consent_confirmed_at") instanceof Timestamp);
    await acceptanceStore.recordForClient("client-a", confirmed);
    assert.deepEqual((await reference.get()).get("accepted_at"), stored.get("accepted_at"));
  });

  it("withdrawal blocks new records and dietitian reads without deleting existing data", async () => {
    const [clientToken, dietitianToken, adminToken] = await Promise.all([
      signIn("client-a@fitnep.test"), signIn("dietitian@fitnep.test"), signIn("admin@fitnep.test"),
    ]);
    const client = bearer(clientToken);
    const dietitian = bearer(dietitianToken);
    const assignment = firestore.collection("client_assignments").doc("client-a");
    await assignment.set({ active: true, dietitian_id: "dietitian-1" });
    const activity = "/clients/client-a/records/activity-data";
    const progress = "/clients/client-a/records/progress-photos";
    const prefs = "/privacy/preferences";
    const sample = { steps: 1000, active_minutes: 30 };
    const photo = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN84AAAAASUVORK5CYII=", "base64");

    await request(api).post(activity).set(client).send(sample).expect(403);
    await request(api).patch(prefs).set(client).send({ share_progress_photos: true }).expect(200);
    await request(api).post(activity).set(client).send(sample).expect(403);
    const created = await request(api).post(progress).set(client).type("png").send(photo).expect(201);
    const imagePath = `${progress}/${created.body.data.record.id}/photo`;
    await request(api).get(imagePath).set(dietitian).expect(200).expect("Content-Type", "image/png");
    await request(api).get(imagePath).set(bearer(adminToken)).expect(403);
    await request(api).patch(prefs).set(client).send({ share_activity_data: true }).expect(200);
    await request(api).post(activity).set(client).send(sample).expect(201);
    await request(api).get(activity).set(dietitian).expect(200);
    await assignment.update({ dietitian_id: "replacement" });
    await request(api).get(activity).set(dietitian).expect(403);
    await assignment.update({ dietitian_id: "dietitian-1" });

    await request(api).patch(prefs).set(client)
      .send({ share_activity_data: false, share_progress_photos: false }).expect(200);
    await request(api).post(activity).set(client).send(sample).expect(403);
    await request(api).post(progress).set(client).type("png").send(photo).expect(403);
    await request(api).get(activity).set(dietitian).expect(403);
    await request(api).get(imagePath).set(dietitian).expect(403);
    await request(api).get(imagePath).set(client).expect(200);
    const own = await request(api).get(activity).set(client).expect(200);
    assert.deepEqual(own.body.data.records.map((record: { details: unknown }) => record.details), [sample]);
  });

  it("enforces ownership with real emulator ID tokens and persisted records", async () => {
    const [clientAToken, clientBToken, dietitianToken] = await Promise.all([
      signIn("client-a@fitnep.test"),
      signIn("client-b@fitnep.test"),
      signIn("dietitian@fitnep.test"),
    ]);
    const created = await workflows.dietPlanAssigned(
      { uid: "dietitian-1", role: "dietitian" },
      { planId: "plan-emulator", clientId: "client-a" },
    );

    const clientAList = await request(api)
      .get("/notifications")
      .set(bearer(clientAToken));
    const clientBList = await request(api)
      .get("/notifications")
      .set(bearer(clientBToken));
    const clientBDirect = await request(api)
      .get(`/notifications/${created.notification.id}`)
      .set(bearer(clientBToken));
    const clientBMark = await request(api)
      .patch(`/notifications/${created.notification.id}/read`)
      .set(bearer(clientBToken));
    const dietitianList = await request(api)
      .get("/notifications")
      .set(bearer(dietitianToken));
    const directFirestoreRead = await fetch(
      firestoreDocumentUrl(created.notification.id),
      { headers: bearer(clientAToken) },
    );
    const directFirestoreWrite = await fetch(
      firestoreDocumentUrl(created.notification.id),
      {
        method: "PATCH",
        headers: {
          ...bearer(clientAToken),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fields: { is_read: { booleanValue: true } },
        }),
      },
    );

    assert.equal(clientAList.status, 200);
    assert.equal(clientAList.body.data.notifications.length, 1);
    assert.equal(clientBList.status, 200);
    assert.deepEqual(clientBList.body.data.notifications, []);
    assert.equal(clientBDirect.status, 404);
    assert.equal(clientBMark.status, 404);
    assert.deepEqual(dietitianList.body.data.notifications, []);
    assert.equal(directFirestoreRead.status, 403);
    assert.equal(directFirestoreWrite.status, 403);
    assert.equal(
      (
        await repository.getForRecipient(
          created.notification.id,
          "client-a",
        )
      )?.isRead,
      false,
    );

    const readAll = await request(api)
      .patch("/notifications/read-all")
      .set(bearer(clientAToken));
    assert.equal(readAll.status, 200);
    assert.equal(readAll.body.data.updated_count, 1);
  });

  it("persists an admin-created package and returns it to clients", async () => {
    const [adminToken, clientToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("client-a@fitnep.test"),
    ]);
    const payload = {
      request_id: "emulator-package-request",
      name: "Six Month Transformation",
      duration_months: 6,
      price: 12500,
      feature_description: "Training, nutrition, and progress reviews.",
    };

    const createResponse = await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send(payload);
    const repeatedResponse = await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send(payload);
    const clientList = await request(api)
      .get("/packages")
      .set(bearer(clientToken));
    const stored = await firestore
      .collection("packages")
      .doc("emulator-package-request")
      .get();

    assert.equal(createResponse.status, 201);
    assert.equal(repeatedResponse.status, 201);
    assert.equal(clientList.status, 200);
    assert.equal(clientList.body.data.packages.length, 1);
    assert.equal(stored.exists, true);
    assert.equal(stored.get("name"), payload.name);
    assert.equal(stored.get("duration_months"), payload.duration_months);
    assert.equal(stored.get("price"), payload.price);
    assert.equal(
      stored.get("feature_description"),
      payload.feature_description,
    );
  });

  it("persists complete package change history with trusted actor and time", async () => {
    const [adminToken, clientToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("client-a@fitnep.test"),
    ]);
    await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send({
        request_id: "audited-emulator-package",
        name: "Premium",
        duration_months: 3,
        price: 5000,
        feature_description: "Diet Plan, Workout Plan",
        admin_id: "forged-admin",
        admin_name: "Forged Name",
        changed_at: "2000-01-01T00:00:00.000Z",
      })
      .expect(201);
    await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send({
        request_id: "audited-emulator-package",
        name: "Premium",
        duration_months: 3,
        price: 5000,
        feature_description: "Diet Plan, Workout Plan",
      })
      .expect(201);
    await request(api)
      .patch("/packages/audited-emulator-package")
      .set(bearer(adminToken))
      .send({
        name: "Premium Plus",
        duration_months: 6,
        price: 6500,
        feature_description:
          "Diet Plan, Workout Plan, Personal Coaching",
      })
      .expect(200);
    await request(api)
      .patch("/packages/audited-emulator-package/active")
      .set(bearer(adminToken))
      .send({ is_active: false })
      .expect(200);
    await request(api)
      .patch("/packages/audited-emulator-package/active")
      .set(bearer(adminToken))
      .send({ is_active: true })
      .expect(200);

    const storedHistory = await firestore
      .collection("package_change_history")
      .where("package_id", "==", "audited-emulator-package")
      .get();
    assert.equal(storedHistory.size, 4);
    const byAction = new Map(
      storedHistory.docs.map((document) => [document.get("action"), document]),
    );
    const created = byAction.get("created");
    const updated = byAction.get("updated");
    const deactivated = byAction.get("deactivated");
    const activated = byAction.get("activated");
    assert.ok(created !== undefined);
    assert.ok(updated !== undefined);
    assert.ok(deactivated !== undefined);
    assert.ok(activated !== undefined);
    assert.equal(created.get("admin_id"), "admin-1");
    assert.equal(created.get("admin_name"), "FitNep CEO");
    assert.ok(created.get("changed_at") instanceof Timestamp);
    assert.deepEqual(updated.get("previous_values"), {
      name: "Premium",
      duration_months: 3,
      price: 5000,
      feature_description: "Diet Plan, Workout Plan",
    });
    assert.deepEqual(updated.get("new_values"), {
      name: "Premium Plus",
      duration_months: 6,
      price: 6500,
      feature_description:
        "Diet Plan, Workout Plan, Personal Coaching",
    });
    assert.deepEqual(deactivated.get("previous_values"), { is_active: true });
    assert.deepEqual(deactivated.get("new_values"), { is_active: false });
    assert.deepEqual(activated.get("previous_values"), { is_active: false });
    assert.deepEqual(activated.get("new_values"), { is_active: true });

    const historyResponse = await request(api)
      .get("/admin/package-history")
      .set(bearer(adminToken))
      .expect(200);
    assert.equal(historyResponse.body.data.history.length, 4);
    await request(api)
      .get("/admin/package-history")
      .set(bearer(clientToken))
      .expect(403);

    const directRead = await fetch(firestorePackageHistoryCollectionUrl(), {
      headers: bearer(clientToken),
    });
    const directWrite = await fetch(
      `${firestorePackageHistoryCollectionUrl()}/forged-history`,
      {
        method: "PATCH",
        headers: {
          ...bearer(clientToken),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fields: {
            admin_id: { stringValue: "forged-admin" },
            changed_at: { timestampValue: "2000-01-01T00:00:00.000Z" },
          },
        }),
      },
    );
    assert.equal(directRead.status, 403);
    assert.equal(directWrite.status, 403);

    const restartedApi = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      packageRepository: new FirestorePackageRepository(firestore),
      purchaseRepository: new FirestorePurchaseRepository(firestore),
    });
    const afterRestart = await request(restartedApi)
      .get("/admin/package-history")
      .set(bearer(adminToken))
      .expect(200);
    assert.equal(afterRestart.body.data.history.length, 4);
  });

  it("keeps customer A's purchased terms after package edits and snapshots new terms for customer B", async () => {
    const [adminToken, clientAToken, clientBToken] = await Promise.all([
      signIn("admin@fitnep.test"),
      signIn("client-a@fitnep.test"),
      signIn("client-b@fitnep.test"),
    ]);
    await request(api)
      .post("/packages")
      .set(bearer(adminToken))
      .send({
        request_id: "premium-emulator-package",
        name: "Premium",
        duration_months: 3,
        price: 5000,
        feature_description: "Diet Plan, Workout Plan, Weekly Consultation",
      })
      .expect(201);

    const customerAPurchase = await request(api)
      .post("/purchases")
      .set(bearer(clientAToken))
      .send({
        package_id: "premium-emulator-package",
        request_id: "customer-a-emulator-purchase",
      })
      .expect(201);

    assert.equal(customerAPurchase.body.data.purchase.status, "pending");
    assert.equal(customerAPurchase.body.data.purchase.purchased_at, null);
    assert.equal(customerAPurchase.body.data.purchase.expires_at, null);
    const approvalPath = `/admin/memberships/${customerAPurchase.body.data.purchase.id}/verify-payment`;
    await request(api).post(approvalPath).set(bearer(clientAToken))
      .send({ reference: "CLIENT-BYPASS" }).expect(403);
    await request(api).post(approvalPath).set(bearer(adminToken))
      .send({ reference: "VERIFIED-A" }).expect(200);
    const activatedA = await request(api).get("/purchases/current")
      .set(bearer(clientAToken)).expect(200);
    assert.equal(activatedA.body.data.purchase.status, "active");

    await request(api)
      .patch("/packages/premium-emulator-package")
      .set(bearer(adminToken))
      .send({
        name: "Premium",
        duration_months: 6,
        price: 6500,
        feature_description:
          "Diet Plan, Workout Plan, Personal Coaching, Priority Consultation",
      })
      .expect(200);

    const customerAAfterEdit = await request(api)
      .get("/purchases/current")
      .set(bearer(clientAToken))
      .expect(200);
    const customerBPurchase = await request(api)
      .post("/purchases")
      .set(bearer(clientBToken))
      .send({
        package_id: "premium-emulator-package",
        request_id: "customer-b-emulator-purchase",
      })
      .expect(201);

    assert.equal(customerAAfterEdit.body.data.purchase.package_name, "Premium");
    assert.equal(customerAAfterEdit.body.data.purchase.price_paid, 5000);
    assert.equal(customerAAfterEdit.body.data.purchase.duration_months, 3);
    assert.equal(
      customerAAfterEdit.body.data.purchase.feature_description,
      "Diet Plan, Workout Plan, Weekly Consultation",
    );
    assert.equal(
      customerAAfterEdit.body.data.purchase.purchased_at,
      activatedA.body.data.purchase.purchased_at,
    );
    assert.equal(
      customerAAfterEdit.body.data.purchase.expires_at,
      activatedA.body.data.purchase.expires_at,
    );
    assert.equal(
      activatedA.body.data.purchase.expires_at,
      addCalendarMonths(
        new Date(activatedA.body.data.purchase.purchased_at as string),
        3,
      ).toISOString(),
    );
    assert.equal(customerBPurchase.body.data.purchase.price_paid, 6500);
    assert.equal(customerBPurchase.body.data.purchase.duration_months, 6);
    assert.equal(
      customerBPurchase.body.data.purchase.feature_description,
      "Diet Plan, Workout Plan, Personal Coaching, Priority Consultation",
    );

    const storedA = await firestore
      .collection("package_memberships")
      .doc(customerAPurchase.body.data.purchase.id as string)
      .get();
    assert.equal(storedA.get("package.price_npr"), 5000);
    assert.equal(storedA.get("package.duration_months"), 3);
    assert.equal(customerBPurchase.body.data.purchase.status, "pending");
    const repeatedSelection = await request(api).post("/memberships")
      .set(bearer(clientBToken))
      .send({ package_id: "premium-emulator-package", request_id: "client-b-shared-selection" })
      .expect(200);
    assert.equal(repeatedSelection.body.data.membership.id, customerBPurchase.body.data.purchase.id);

    const restartedApi = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      packageRepository: new FirestorePackageRepository(firestore),
      purchaseRepository: new FirestorePurchaseRepository(firestore),
    });
    const afterRestart = await request(restartedApi)
      .get("/purchases/current")
      .set(bearer(clientAToken))
      .expect(200);
    assert.equal(afterRestart.body.data.purchase.price_paid, 5000);
    assert.equal(
      afterRestart.body.data.purchase.expires_at,
      activatedA.body.data.purchase.expires_at,
    );
  });
});

async function createAccount(
  auth: Auth,
  uid: string,
  email: string,
  role: UserRole,
  displayName?: string,
): Promise<void> {
  await auth.createUser({
    uid,
    email,
    password: "Password123!",
    ...(displayName === undefined ? {} : { displayName }),
  });
  await auth.setCustomUserClaims(uid, { role });
}

async function signIn(email: string): Promise<string> {
  const response = await fetch(
    `http://${authEmulatorHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email,
        password: "Password123!",
        returnSecureToken: true,
      }),
    },
  );
  const body = (await response.json()) as { idToken?: string };
  if (!response.ok || body.idToken === undefined) {
    throw new Error(`Auth emulator sign-in failed: ${response.status}`);
  }
  return body.idToken;
}

async function clearAuth(): Promise<void> {
  const response = await fetch(
    `http://${authEmulatorHost}/emulator/v1/projects/${projectId}/accounts`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Could not clear Auth emulator: ${response.status}`);
  }
}

async function clearFirestore(): Promise<void> {
  const response = await fetch(
    `http://${firestoreEmulatorHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Could not clear Firestore emulator: ${response.status}`);
  }
}

function bearer(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` };
}

function firestoreDocumentUrl(notificationId: string): string {
  return `http://${firestoreEmulatorHost}/v1/projects/${projectId}/databases/(default)/documents/notifications/${notificationId}`;
}

function firestorePackageHistoryCollectionUrl(): string {
  return `http://${firestoreEmulatorHost}/v1/projects/${projectId}/databases/(default)/documents/package_change_history`;
}
