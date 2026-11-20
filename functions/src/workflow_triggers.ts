import { logger } from "firebase-functions";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";

import { AuthenticatedUser, normalizeUserRole } from "./domain";
import {
  InvalidWorkflowEventError,
  NotificationWorkflowService,
  PaymentStatus,
  WorkflowAuthorizationError,
} from "./notification_service";

const region = "asia-south1";

export function createNotificationWorkflowTriggers(
  workflows: NotificationWorkflowService,
) {
  return {
    dietPlanAssigned: onDocumentCreated(
      { document: "diet_plans/{planId}", region },
      async (event) => {
        const snapshot = event.data;
        if (snapshot === undefined) return;
        await runWorkflow("diet plan assignment", async () => {
          const data = snapshot.data();
          await workflows.dietPlanAssigned(actorFrom(data), {
            planId: event.params.planId,
            clientId: requiredField(data, ["client_id", "clientId"]),
            planTitle: optionalString(data.title),
          });
        });
      },
    ),

    messageReceived: onDocumentCreated(
      { document: "messages/{messageId}", region },
      async (event) => {
        const snapshot = event.data;
        if (snapshot === undefined) return;
        await runWorkflow("message receipt", async () => {
          const data = snapshot.data();
          await workflows.messageReceived({
            messageId: event.params.messageId,
            conversationId: requiredField(
              data,
              ["conversation_id", "conversationId"],
            ),
            recipientId: requiredField(data, ["recipient_id", "recipientId"]),
            senderName: optionalField(data, ["sender_name", "senderName"]),
          });
        });
      },
    ),

    taskAssigned: onDocumentCreated(
      { document: "tasks/{taskId}", region },
      async (event) => {
        const snapshot = event.data;
        if (snapshot === undefined) return;
        await runWorkflow("task assignment", async () => {
          const data = snapshot.data();
          await workflows.taskAssigned(actorFrom(data), {
            taskId: event.params.taskId,
            assigneeId: requiredField(data, ["assignee_id", "assigneeId"]),
            taskTitle: optionalString(data.title),
          });
        });
      },
    ),

    paymentConfirmed: onDocumentUpdated(
      { document: "payments/{paymentId}", region },
      async (event) => {
        const before = event.data?.before.data();
        const after = event.data?.after.data();
        if (before === undefined || after === undefined) return;

        const beforeStatus = paymentStatus(before.status);
        const afterStatus = paymentStatus(after.status);
        if (!isSuccessful(afterStatus) || isSuccessful(beforeStatus)) return;

        await runWorkflow("payment confirmation", async () => {
          await workflows.paymentStatusChanged({
            paymentId: event.params.paymentId,
            recipientId: requiredField(after, ["recipient_id", "recipientId"]),
            status: afterStatus,
            amountLabel: optionalField(after, ["amount_label", "amountLabel"]),
          });
        });
      },
    ),
  };
}

function actorFrom(data: Record<string, unknown>): AuthenticatedUser {
  const uid = requiredField(data, ["assigned_by_id", "assignedById"]);
  const role = normalizeUserRole(
    requiredField(data, ["assigned_by_role", "assignedByRole"]),
  );
  if (role === null) {
    throw new InvalidWorkflowEventError("assignedByRole is invalid.");
  }
  return { uid, role };
}

function requiredField(
  data: Record<string, unknown>,
  names: readonly string[],
): string {
  for (const name of names) {
    const value = optionalString(data[name]);
    if (value !== undefined) return value;
  }
  throw new InvalidWorkflowEventError(`${names[0]} is required.`);
}

function optionalField(
  data: Record<string, unknown>,
  names: readonly string[],
): string | undefined {
  for (const name of names) {
    const value = optionalString(data[name]);
    if (value !== undefined) return value;
  }
  return undefined;
}

function optionalString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim();
  return normalized.length === 0 ? undefined : normalized;
}

function paymentStatus(value: unknown): PaymentStatus | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return ["paid", "confirmed", "succeeded", "pending", "failed"].includes(
    normalized,
  )
    ? (normalized as PaymentStatus)
    : null;
}

function isSuccessful(status: PaymentStatus | null): status is PaymentStatus {
  return status === "paid" || status === "confirmed" || status === "succeeded";
}

async function runWorkflow(
  workflowName: string,
  action: () => Promise<void>,
): Promise<void> {
  try {
    await action();
  } catch (error) {
    if (
      error instanceof InvalidWorkflowEventError ||
      error instanceof WorkflowAuthorizationError
    ) {
      logger.error(`Rejected invalid ${workflowName} notification event.`, {
        error: error.message,
      });
      return;
    }
    throw error;
  }
}
