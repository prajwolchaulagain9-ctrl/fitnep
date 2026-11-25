import { applicationDefault, cert, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import { createFitnepDependencies } from "./api_factory";
import { mountHostedAuth } from "./hosted_auth";
import { HostedConfigurationError, readHostedConfig } from "./hosted_config";
import { createNotificationApp } from "./http_app";
import { FirestorePlatformSessionService } from "./platform_sessions";
<<<<<<< HEAD
import {
  ClientAssignmentService,
  ExistingClientPackageStatusReader,
  ExistingStaffDietitianDirectory,
  FirebaseClientDirectory,
} from "./client_assignment_service";
import { FirestoreClientAssignmentRepository } from "./firestore_client_assignment_repository";
import { NotificationWorkflowService } from "./notification_service";
import { ClientIntakeService } from "./client_intake_service";
import { FirestoreClientIntakeRepository } from "./firestore_client_intake_repository";
=======
>>>>>>> c499eb6a8ddbbd3a04b036c74ccf5066f5046e48

function start() {
  const config = readHostedConfig(process.env);
  const firebase = initializeApp({
    projectId: config.projectId,
    credential: config.serviceAccount ? cert(config.serviceAccount) : applicationDefault(),
  });
  const auth = getAuth(firebase);
  const firestore = getFirestore(firebase);
<<<<<<< HEAD
  const audit = new FirestoreAuditWriter(firestore);
  const privacy = new FirestorePrivacyPreferencesRepository(firestore);
  const packageMemberships = new FirestorePackageService(firestore);
  const purchases = new FirestorePurchaseRepository(firestore);
  const staffAccounts = new FirebaseStaffAccountRepository(auth, firestore);
  const app = createNotificationApp({
    authVerifier: new FirebaseAuthVerifier(auth),
    notificationRepository: new FirestoreNotificationRepository(firestore),
    staffAccountRepository: staffAccounts,
    packageService: packageMemberships,
    packageRepository: new FirestorePackageRepository(firestore),
    purchaseRepository: purchases,
    clientAssignmentService: new ClientAssignmentService(
      new FirestoreClientAssignmentRepository(firestore, audit),
      new ExistingClientPackageStatusReader(packageMemberships),
      new ExistingStaffDietitianDirectory(staffAccounts),
      new NotificationWorkflowService(new FirestoreNotificationRepository(firestore)),
      new FirebaseClientDirectory(auth),
    ),
    clientIntakeService: new ClientIntakeService(
      new FirestoreClientIntakeRepository(firestore),
    ),
    privacyPreferencesRepository: privacy,
    privateRecordsStore: new FirestorePrivateRecordsStore(firestore, privacy),
    platformSessions: new FirestorePlatformSessionService(firestore, audit, config.idleTimeoutSeconds),
    auditWriter: audit,
=======
  const dependencies = createFitnepDependencies(auth, firestore);
  const authAdapter = mountHostedAuth(auth, firestore, dependencies.authVerifier, process.env);
  const api = createNotificationApp({
    ...dependencies,
    platformSessions: new FirestorePlatformSessionService(firestore, dependencies.auditWriter, config.idleTimeoutSeconds),
>>>>>>> c499eb6a8ddbbd3a04b036c74ccf5066f5046e48
    manualVerificationEnabled: false,
    health: {
      buildSha: config.buildSha,
      checkReady: async () => { await firestore.doc("_runtime/health").get(); },
    },
  });
  const app = authAdapter;
  app.use(api);
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
