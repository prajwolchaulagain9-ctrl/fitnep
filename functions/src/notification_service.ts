import { randomUUID } from "node:crypto";

import { AuthenticationError } from "./auth";
import {
  AuthenticatedUser,
  CreateNotificationResult,
  NewNotification,
  NotificationRecord,
} from "./domain";
import {
  ProtectedAction,
  roleCanPerformAction,
  PermissionDeniedError,
} from "./authorization_policy";
import { NotificationRepository } from "./notification_repository";

export class NotificationNotFoundError extends PermissionDeniedError {
  constructor() {
    super("The notification is outside this account.");
    this.name = "NotificationNotFoundError";
  }
}

export class WorkflowAuthorizationError extends Error {
  constructor() {
    super("This account cannot perform the notification workflow.");
    this.name = "WorkflowAuthorizationError";
  }
}

export class InvalidWorkflowEventError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidWorkflowEventError";
  }
}

export class NotificationService {
  constructor(private readonly repository: NotificationRepository) {}

  async list(user: AuthenticatedUser): Promise<NotificationRecord[]> {
    requireNotificationAccess(user, "readOwnNotifications");
    const notifications = await this.repository.listForRecipient(user.uid);
    return [...notifications].sort((left, right) =>
      right.createdAt.localeCompare(left.createdAt),
    );
  }

  async get(
    user: AuthenticatedUser,
    notificationId: string,
  ): Promise<NotificationRecord> {
    requireNotificationAccess(user, "readOwnNotifications");
    const notification = await this.repository.getForRecipient(
      requireIdentifier(notificationId, "notificationId"),
      user.uid,
    );
    if (notification === null) throw new NotificationNotFoundError();
    return notification;
  }

  async markRead(
    user: AuthenticatedUser,
    notificationId: string,
  ): Promise<NotificationRecord> {
    requireNotificationAccess(user, "updateOwnNotifications");
    const notification = await this.repository.markReadForRecipient(
      requireIdentifier(notificationId, "notificationId"),
      user.uid,
    );
    if (notification === null) throw new NotificationNotFoundError();
    return notification;
  }

  markAllRead(user: AuthenticatedUser): Promise<number> {
    requireNotificationAccess(user, "updateOwnNotifications");
    return this.repository.markAllReadForRecipient(user.uid);
  }
}

function requireNotificationAccess(
  user: AuthenticatedUser,
  action: "readOwnNotifications" | "updateOwnNotifications",
): void {
  if (!roleCanPerformAction(user.role, action)) {
    throw new AuthenticationError("This account cannot access notifications.", 403);
  }
}

export interface DietPlanAssignedEvent {
  planId: string;
  clientId: string;
  planTitle?: string;
}

export interface MessageReceivedEvent {
  messageId: string;
  conversationId: string;
  recipientId: string;
  senderName?: string;
}

export interface TaskAssignedEvent {
  taskId: string;
  assigneeId: string;
  taskTitle?: string;
}

export type PaymentStatus =
  | "paid"
  | "confirmed"
  | "succeeded"
  | "pending"
  | "failed";

export interface PaymentStatusChangedEvent {
  paymentId: string;
  recipientId: string;
  status: PaymentStatus;
  amountLabel?: string;
}

export interface NotificationWorkflowOptions {
  now?: () => Date;
  idFactory?: () => string;
}

export class NotificationWorkflowService {
  private readonly now: () => Date;
  private readonly idFactory: () => string;

  constructor(
    private readonly repository: NotificationRepository,
    options: NotificationWorkflowOptions = {},
  ) {
    this.now = options.now ?? (() => new Date());
    this.idFactory = options.idFactory ?? randomUUID;
  }

  dietPlanAssigned(
    actor: AuthenticatedUser,
    event: DietPlanAssignedEvent,
  ): Promise<CreateNotificationResult> {
    requireWorkflowAction(actor, "createDietPlanAssignmentNotification");
    const planId = requireIdentifier(event.planId, "planId");
    const clientId = requireIdentifier(event.clientId, "clientId");
    return this.create({
      recipientId: clientId,
      type: "diet_plan",
      referenceId: planId,
      eventKey: `diet-plan:${planId}:assigned:${clientId}`,
      title: event.planTitle?.trim() || "New diet plan assigned",
      message: "A new diet plan is ready for you to review.",
    });
  }

  messageReceived(
    event: MessageReceivedEvent,
  ): Promise<CreateNotificationResult> {
    const messageId = requireIdentifier(event.messageId, "messageId");
    const conversationId = requireIdentifier(
      event.conversationId,
      "conversationId",
    );
    const recipientId = requireIdentifier(event.recipientId, "recipientId");
    const senderName = event.senderName?.trim();
    return this.create({
      recipientId,
      type: "message",
      referenceId: conversationId,
      eventKey: `message:${messageId}:received:${recipientId}`,
      title: senderName ? `New message from ${senderName}` : "New message",
      message: "You received a new message in FitNep.",
    });
  }

  taskAssigned(
    actor: AuthenticatedUser,
    event: TaskAssignedEvent,
  ): Promise<CreateNotificationResult> {
    requireWorkflowAction(actor, "createTaskAssignmentNotification");
    const taskId = requireIdentifier(event.taskId, "taskId");
    const assigneeId = requireIdentifier(event.assigneeId, "assigneeId");
    return this.create({
      recipientId: assigneeId,
      type: "task",
      referenceId: taskId,
      eventKey: `task:${taskId}:assigned:${assigneeId}`,
      title: event.taskTitle?.trim() || "New task assigned",
      message: "A new task has been assigned to you.",
    });
  }

  paymentStatusChanged(
    event: PaymentStatusChangedEvent,
  ): Promise<CreateNotificationResult | null> {
    if (!["paid", "confirmed", "succeeded"].includes(event.status)) {
      return Promise.resolve(null);
    }

    const paymentId = requireIdentifier(event.paymentId, "paymentId");
    const recipientId = requireIdentifier(event.recipientId, "recipientId");
    const amount = event.amountLabel?.trim();
    return this.create({
      recipientId,
      type: "payment",
      referenceId: paymentId,
      eventKey: `payment:${paymentId}:confirmed:${recipientId}`,
      title: "Payment confirmed",
      message: amount
        ? `Your payment of ${amount} was completed successfully.`
        : "Your payment was completed successfully.",
    });
  }

  private create(
    notification: Omit<NewNotification, "id" | "createdAt">,
  ): Promise<CreateNotificationResult> {
    return this.repository.createIfAbsent({
      ...notification,
      id: this.idFactory(),
      createdAt: this.now().toISOString(),
    });
  }
}

function requireWorkflowAction(
  actor: AuthenticatedUser,
  action: ProtectedAction,
): void {
  if (!roleCanPerformAction(actor.role, action)) {
    throw new WorkflowAuthorizationError();
  }
}

export function requireIdentifier(value: string, field: string): string {
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > 160) {
    throw new InvalidWorkflowEventError(`${field} is invalid.`);
  }
  return normalized;
}
