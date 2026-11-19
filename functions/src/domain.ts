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

export interface PackageRecord {
  id: string;
  name: string;
  durationMonths: number;
  price: number;
  featureDescription: string;
  isActive: boolean;
  createdAt: string;
  createdBy: string;
  requestId: string;
}

export interface NewPackage {
  name: string;
  durationMonths: number;
  price: number;
  featureDescription: string;
  createdBy: string;
  requestId: string;
}

export interface UpdatePackageInput {
  name: string;
  durationMonths: number;
  price: number;
  featureDescription: string;
  updatedBy: string;
}

export interface CreatePackageResult {
  package: PackageRecord;
  created: boolean;
}

export interface PurchaseRecord {
  id: string;
  customerId: string;
  packageId: string;
  packageName: string;
  pricePaid: number;
  durationMonths: number;
  featureDescription: string;
  purchasedAt: string;
  expiresAt: string;
  requestId: string;
}

export interface CreatePurchaseResult {
  purchase: PurchaseRecord;
  created: boolean;
}

export function isUserRole(value: unknown): value is UserRole {
  return typeof value === "string" &&
    userRoles.includes(value.toLowerCase() as UserRole);
}
