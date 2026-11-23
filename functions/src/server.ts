import { applicationDefault, cert, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import { FirestoreAuditWriter } from "./audit";
import { FirebaseAuthVerifier } from "./auth";
import { FirebaseStaffAccountRepository } from "./firebase_staff_account_repository";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { FirestorePackageRepository } from "./firestore_package_repository";
import { FirestorePrivateRecordsStore } from "./firestore_private_records_store";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { FirestorePurchaseRepository } from "./firestore_purchase_repository";
import { HostedConfigurationError, readHostedConfig } from "./hosted_config";
import { createNotificationApp } from "./http_app";
import { FirestorePackageService } from "./package_membership_service";
import { FirestorePlatformSessionService } from "./platform_sessions";

function start() {
  const config = readHostedConfig(process.env);
  const firebase = initializeApp({
    projectId: config.projectId,
    credential: config.serviceAccount ? cert(config.serviceAccount) : applicationDefault(),
  });
  const auth = getAuth(firebase);
  const firestore = getFirestore(firebase);
  const audit = new FirestoreAuditWriter(firestore);
  const privacy = new FirestorePrivacyPreferencesRepository(firestore);
  const app = createNotificationApp({
    authVerifier: new FirebaseAuthVerifier(auth),
    notificationRepository: new FirestoreNotificationRepository(firestore),
    staffAccountRepository: new FirebaseStaffAccountRepository(auth, firestore),
    packageService: new FirestorePackageService(firestore),
    packageRepository: new FirestorePackageRepository(firestore),
    purchaseRepository: new FirestorePurchaseRepository(firestore),
    privacyPreferencesRepository: privacy,
    privateRecordsStore: new FirestorePrivateRecordsStore(firestore, privacy, audit),
    platformSessions: new FirestorePlatformSessionService(firestore, audit, config.idleTimeoutSeconds),
    auditWriter: audit,
    manualVerificationEnabled: false,
    health: {
      buildSha: config.buildSha,
      checkReady: async () => { await firestore.doc("_runtime/health").get(); },
    },
  });
  // Render terminates HTTPS and forwards to the assigned PORT.
  const server = app.listen(config.port, "0.0.0.0", () => {
    console.log("FitNEP API listening on port " + config.port + "; build " + config.buildSha);
  });
  server.on("error", () => {
    console.error("The FitNEP API could not bind its configured port.");
    void deleteApp(firebase).finally(() => { process.exitCode = 1; });
  });
  const close = () => {
    const deadline = setTimeout(() => process.exit(1), 10_000);
    deadline.unref();
    server.close(() => { void deleteApp(firebase).finally(() => process.exit(0)); });
  };
  process.once("SIGINT", close);
  process.once("SIGTERM", close);
}

try { start(); } catch (error) {
  console.error(error instanceof HostedConfigurationError
    ? error.message
    : "The FitNEP API could not initialize. Check the host's Firebase credentials.");
  process.exitCode = 1;
}
