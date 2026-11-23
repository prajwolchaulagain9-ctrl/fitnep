export const staffAccountRoles = ["admin", "dietitian", "staff"] as const;
export type StaffAccountRole = (typeof staffAccountRoles)[number];

export const userRoles = [...staffAccountRoles, "client"] as const;
export type UserRole = (typeof userRoles)[number];

/** Returns the canonical role for a value from a trusted identity source. */
export function normalizeUserRole(value: unknown): UserRole | null {
  if (typeof value !== "string") return null;

  const normalized = value.trim().toLowerCase();
  return userRoles.find((role) => role === normalized) ?? null;
}

export interface AuthenticatedUser {
  uid: string;
  role: UserRole;
  displayName?: string;
  email?: string;
  passwordAuthenticatedAt?: number;
  staffRoleVersion?: string;
  roleVersion?: number;
  authTime?: number;
  emailVerified?: boolean;
  mustChangePassword?: boolean;
  permissions?: {
    auditRead: boolean;
    paymentsVerify: boolean;
  };
}

export interface StaffAccount {
  uid: string;
  name: string | null;
  email: string | null;
  role: StaffAccountRole;
  isActive: boolean;
}

export const notificationTypes = [
  "diet_plan",
  "message",
  "task",
  "payment",
  "assignment",
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
  createdByName: string;
  requestId: string;
}

export interface UpdatePackageInput {
  name: string;
  durationMonths: number;
  price: number;
  featureDescription: string;
  updatedBy: string;
  updatedByName: string;
}

export interface SetPackageActiveStatusInput {
  isActive: boolean;
  updatedBy: string;
  updatedByName: string;
}

export const packageHistoryActions = [
  "created",
  "updated",
  "activated",
  "deactivated",
] as const;
export type PackageHistoryAction = (typeof packageHistoryActions)[number];

export interface PackageHistoryValues {
  name?: string;
  durationMonths?: number;
  price?: number;
  featureDescription?: string;
  isActive?: boolean;
}

export interface PackageChangeHistoryRecord {
  id: string;
  packageId: string;
  packageName: string;
  adminId: string;
  adminName: string;
  action: PackageHistoryAction;
  previousValues: PackageHistoryValues | null;
  newValues: PackageHistoryValues;
  changedAt: string;
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
  purchasedAt: string | null;
  expiresAt: string | null;
  requestId: string;
  status?: "pending" | "active" | "scheduled" | "expired";
  daysRemaining?: number;
  durationDays?: number;
}

export interface CreatePurchaseResult {
  purchase: PurchaseRecord;
  created: boolean;
}

export function isUserRole(value: unknown): value is UserRole {
  return typeof value === "string" && userRoles.includes(value as UserRole);
}
