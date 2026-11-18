export const userRoles = ["admin", "dietitian", "client"] as const;
export type UserRole = (typeof userRoles)[number];

export interface AuthenticatedUser {
  uid: string;
  role: UserRole;
}

export const notificationTypes = [
  "diet_plan",
  "message",
  "task",
  "payment",
] as const;
export type NotificationType = (typeof notificationTypes)[number];

export interface NotificationRecord {
  id: string;
  recipientId: string;
  title: string;
  message: string;
  type: NotificationType;
  referenceId: string;
  isRead: boolean;
  createdAt: string;
  eventKey: string;
}

export interface NewNotification {
  id: string;
  recipientId: string;
  title: string;
  message: string;
  type: NotificationType;
  referenceId: string;
  eventKey: string;
  createdAt?: string;
}

export interface CreateNotificationResult {
  notification: NotificationRecord;
  created: boolean;
}

export function isUserRole(value: unknown): value is UserRole {
  return typeof value === "string" &&
    userRoles.includes(value.toLowerCase() as UserRole);
}
