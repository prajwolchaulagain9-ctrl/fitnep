import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

import { FirebaseAuthVerifier } from "./auth";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { createNotificationApp } from "./http_app";
import { NotificationWorkflowService } from "./notification_service";
import { createNotificationWorkflowTriggers } from "./workflow_triggers";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { FirestorePackageService, PackageError } from "./package_service";

if (getApps().length === 0) initializeApp();

// Both entry points share the same Admin app and revocation-aware verifier.
export const checkSession = require("../src/index.cjs").checkSession;

const notificationRepository = new FirestoreNotificationRepository(
  getFirestore(),
);
const privacyPreferencesRepository = new FirestorePrivacyPreferencesRepository(
  getFirestore(),
);
const packageService = new FirestorePackageService(getFirestore());
const notificationApp = createNotificationApp({
  authVerifier: new FirebaseAuthVerifier(),
  notificationRepository,
  privacyPreferencesRepository,
  packageService,
});
const workflowTriggers = createNotificationWorkflowTriggers(
  new NotificationWorkflowService(notificationRepository),
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
