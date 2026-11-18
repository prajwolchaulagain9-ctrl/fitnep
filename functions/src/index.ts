import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { onRequest } from "firebase-functions/v2/https";

import { FirebaseAuthVerifier } from "./auth";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { createNotificationApp } from "./http_app";
import { NotificationWorkflowService } from "./notification_service";
import { createNotificationWorkflowTriggers } from "./workflow_triggers";

if (getApps().length === 0) initializeApp();

// Both entry points share the same Admin app and revocation-aware verifier.
export const checkSession = require("../src/index.cjs").checkSession;

const notificationRepository = new FirestoreNotificationRepository(
  getFirestore(),
);
const notificationApp = createNotificationApp({
  authVerifier: new FirebaseAuthVerifier(),
  notificationRepository,
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
