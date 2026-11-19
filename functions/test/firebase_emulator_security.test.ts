import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore } from "firebase-admin/firestore";
import request from "supertest";

import { FirebaseAuthVerifier } from "../src/auth";
import { UserRole } from "../src/domain";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
import { FirestorePackageRepository } from "../src/firestore_package_repository";
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
  let api: ReturnType<typeof createNotificationApp>;

  before(() => {
    firebaseApp = initializeApp({ projectId });
    auth = getAuth(firebaseApp);
    firestore = getFirestore(firebaseApp);
    repository = new FirestoreNotificationRepository(firestore);
    packageRepository = new FirestorePackageRepository(firestore);
    workflows = new NotificationWorkflowService(repository);
    api = createNotificationApp({
      authVerifier: new FirebaseAuthVerifier(),
      notificationRepository: repository,
      packageRepository,
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
      createAccount(auth, "admin-1", "admin@fitnep.test", "admin"),
    ]);
  });

  after(async () => {
    await deleteApp(firebaseApp);
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
});

async function createAccount(
  auth: Auth,
  uid: string,
  email: string,
  role: UserRole,
): Promise<void> {
  await auth.createUser({ uid, email, password: "Password123!" });
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
