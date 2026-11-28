import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { createFitnepDependencies } from "./api_factory";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";

import { createNotificationApp } from "./http_app";
import { NotificationWorkflowService } from "./notification_service";
import { createNotificationWorkflowTriggers } from "./workflow_triggers";
import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { PackageError } from "./package_membership_service";
import { HostedWorkflowDelivery } from "./workflow_delivery";

if (getApps().length === 0) initializeApp();

// Both entry points share the same Admin app and revocation-aware verifier.
export const checkSession = require("../src/index.cjs").checkSession;
export { registrationPrivacy } from "./registration_privacy";
export { sendSignupEmailCode, verifySignupEmailCode } from "./signup_email_codes";

const db = getFirestore();
const dependencies = createFitnepDependencies(getAuth(), db);
const packageService = dependencies.packageService;
const cloudinaryUrl = defineSecret("CLOUDINARY_URL");
let notificationApp: ReturnType<typeof createNotificationApp> | undefined;
const delivery = new HostedWorkflowDelivery(db);
const workflowTriggers = createNotificationWorkflowTriggers(
  new NotificationWorkflowService(dependencies.notificationRepository),
);

export const api = onRequest(
  {
    region: "asia-south1",
    invoker: "public",
    maxInstances: 10,
    secrets: [cloudinaryUrl],
  },
  (request, response) => {
    notificationApp ??= createNotificationApp(createFitnepDependencies(getAuth(), db));
    notificationApp(request, response);
  },
);

export const onDietPlanAssigned = workflowTriggers.dietPlanAssigned;
export const onMessageReceived = workflowTriggers.messageReceived;
export const onTaskAssigned = workflowTriggers.taskAssigned;
export const onPaymentConfirmed = workflowTriggers.paymentConfirmed;

export const deliverWorkflowOutbox = onDocumentCreated(
  { document: "workflow_outbox/{id}", region: "asia-south1", retry: true },
  async event => {
    const kind = event.data?.get("event_type");
    if (!["payment.verified", "payment.rejected", "membership.activated", "plan.published"].includes(kind)) return;
    await delivery.drain(event.params.id);
    const state = await db.doc(`outbox_deliveries/${event.params.id}`).get();
    // The shared delivery worker persists its lease and retry schedule.
    if (state.exists && state.get("state") !== "delivered") throw new Error("Workflow delivery will retry.");
  },
);

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
