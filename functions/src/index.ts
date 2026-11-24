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
import { PackageError } from "./package_membership_service";

if (getApps().length === 0) initializeApp();

// Both entry points share the same Admin app and revocation-aware verifier.
export const checkSession = require("../src/index.cjs").checkSession;
export { registrationPrivacy } from "./registration_privacy";
export { sendSignupEmailCode, verifySignupEmailCode } from "./signup_email_codes";

const dependencies = createFitnepDependencies(getAuth(), getFirestore());
const packageService = dependencies.packageService;
const notificationApp = createNotificationApp(dependencies);
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
