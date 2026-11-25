import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { createFitnepDependencies } from "./api_factory";
import { onRequest } from "firebase-functions/v2/https";

import { createNotificationApp } from "./http_app";
import { NotificationWorkflowService } from "./notification_service";
import { createNotificationWorkflowTriggers } from "./workflow_triggers";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
<<<<<<< HEAD
import { FirestorePackageService, PackageError } from "./package_membership_service";
import {
  ClientAssignmentService,
  ExistingClientPackageStatusReader,
  ExistingStaffDietitianDirectory,
  FirebaseClientDirectory,
} from "./client_assignment_service";
import { FirestoreClientAssignmentRepository } from "./firestore_client_assignment_repository";
import { FirestoreAuditWriter } from "./audit";
import { ClientIntakeService } from "./client_intake_service";
import { FirestoreClientIntakeRepository } from "./firestore_client_intake_repository";
=======
import { PackageError } from "./package_membership_service";
>>>>>>> c499eb6a8ddbbd3a04b036c74ccf5066f5046e48

if (getApps().length === 0) initializeApp();

// Both entry points share the same Admin app and revocation-aware verifier.
export const checkSession = require("../src/index.cjs").checkSession;
export { registrationPrivacy } from "./registration_privacy";
export { sendSignupEmailCode, verifySignupEmailCode } from "./signup_email_codes";

<<<<<<< HEAD
const notificationRepository = new FirestoreNotificationRepository(
  getFirestore(),
);
const privacyPreferencesRepository = new FirestorePrivacyPreferencesRepository(getFirestore());
const packageService = new FirestorePackageService(getFirestore());
const packageRepository = new FirestorePackageRepository(getFirestore());
const purchaseRepository = new FirestorePurchaseRepository(getFirestore());
const staffAccountRepository = new FirebaseStaffAccountRepository(getAuth(), getFirestore());
const auditWriter = new FirestoreAuditWriter(getFirestore());
const notificationApp = createNotificationApp({
  authVerifier: new FirebaseAuthVerifier(),
  staffAccountRepository,
  notificationRepository,
  privacyPreferencesRepository,
  privateRecordsStore: new FirestorePrivateRecordsStore(getFirestore(), privacyPreferencesRepository),
  packageService,
  packageRepository,
  purchaseRepository,
  clientAssignmentService: new ClientAssignmentService(
    new FirestoreClientAssignmentRepository(getFirestore(), auditWriter),
    new ExistingClientPackageStatusReader(packageService),
    new ExistingStaffDietitianDirectory(staffAccountRepository),
    new NotificationWorkflowService(notificationRepository),
    new FirebaseClientDirectory(getAuth()),
  ),
  clientIntakeService: new ClientIntakeService(
    new FirestoreClientIntakeRepository(getFirestore()),
  ),
});
=======
const dependencies = createFitnepDependencies(getAuth(), getFirestore());
const packageService = dependencies.packageService;
const notificationApp = createNotificationApp(dependencies);
>>>>>>> c499eb6a8ddbbd3a04b036c74ccf5066f5046e48
const workflowTriggers = createNotificationWorkflowTriggers(
  new NotificationWorkflowService(dependencies.notificationRepository),
);

export const api = onRequest(
  {
    region: "asia-south1",
    invoker: "public",
    maxInstances: 10,
  },
  notificationApp,
);

export const onDietPlanAssigned = workflowTriggers.dietPlanAssigned;
export const onMessageReceived = workflowTriggers.messageReceived;
export const onTaskAssigned = workflowTriggers.taskAssigned;
export const onPaymentConfirmed = workflowTriggers.paymentConfirmed;

export const onPackagePaymentVerified = onDocumentWritten(
  { document: "payments/{paymentId}", region: "asia-south1", retry: true },
  async event => {
    const payment = event.data?.after.data();
    if (!payment?.membership_id || payment.verified !== true || !["paid", "confirmed", "succeeded"].includes(payment.status)) return;
    const before = event.data?.before.data();
    const fields = ["membership_id", "recipient_id", "amount_npr", "currency", "status", "verified", "membership_start_at"];
    if (before && fields.every(field => before[field] === payment[field])) return;
    try {
      await packageService.activateVerifiedPayment(event.params.paymentId);
    } catch (error) {
      if (!(error instanceof PackageError)) throw error;
      logger.error("Rejected package activation", { paymentId: event.params.paymentId, error: error.message });
    }
  },
);
