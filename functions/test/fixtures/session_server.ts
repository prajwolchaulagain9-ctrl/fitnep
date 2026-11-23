// Synthetic emulator-only process fixture. No live credentials or real users.
import { initializeApp, deleteApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { FirestoreAccountService, FirestoreAuditStore } from "../../src/account_service";
import { FirebaseAuthVerifier } from "../../src/auth";
import { FirestoreAuditWriter } from "../../src/audit";
import { FirestorePlatformSessionService } from "../../src/platform_sessions";
import { FirestoreNotificationRepository } from "../../src/firestore_notification_repository";
import { createNotificationApp } from "../../src/http_app";

for (const key of ["FIREBASE_AUTH_EMULATOR_HOST", "FIRESTORE_EMULATOR_HOST"]) {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env[key] ?? "")) throw new Error("Local emulator required.");
}
const firebase = initializeApp({ projectId: "demo-fitnep" });
const db = getFirestore(firebase); const auth = getAuth(firebase);
const accounts = new FirestoreAccountService(db, auth);
const app = createNotificationApp({ accounts, audit: new FirestoreAuditStore(db),
  authVerifier: new FirebaseAuthVerifier(accounts), notificationRepository: new FirestoreNotificationRepository(db),
  platformSessions: new FirestorePlatformSessionService(db, new FirestoreAuditWriter(db), 900,
    () => new Date(Number(process.env.FITNEP_TEST_NOW))),
});
const server = app.listen(0, "127.0.0.1", () => {
  const address = server.address();
  if (address && typeof address !== "string") process.send?.({ port: address.port });
});
process.on("SIGTERM", () => server.close(() => { void deleteApp(firebase).finally(() => process.exit(0)); }));
