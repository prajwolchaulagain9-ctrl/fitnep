import { AuthenticatedUser, UserRole, userRoles } from "./domain";

// Authoritative server policy. Flutter's equivalent controls presentation only.
const own = ["view_dashboard", "view_own_profile", "edit_own_profile",
  "view_own_notifications", "update_own_notifications", "view_own_workflow"] as const;
export const rolePermissions = {
  client: [...own, "view_client_dashboard", "view_packages", "manage_own_membership", "manage_own_privacy",
    "view_client_records", "view_own_client_records", "collect_own_records", "view_own_diet_plans"],
  staff: [...own, "view_staff_dashboard", "view_assigned_clients", "view_client_records", "view_own_diet_plans"],
  dietitian: [...own, "view_dietitian_dashboard", "view_assigned_clients", "view_client_records",
    "view_assigned_client_records", "view_meal_records", "manage_diet_plans", "view_own_diet_plans"],
  admin: [...own, "view_admin_dashboard", "view_packages", "manage_staff_accounts", "manage_dietitian_accounts",
    "manage_client_accounts", "manage_user_roles", "manage_business_settings",
    "view_audit_logs", "manage_client_assignments", "view_client_records", "view_own_diet_plans"],
} as const satisfies Record<UserRole, readonly string[]>;
export type Permission = typeof rolePermissions[UserRole][number];
export const permissions = [...new Set(Object.values(rolePermissions).flat())] as Permission[];
export function hasPermission(role: UserRole, permission: string, auditRead = false): boolean {
  return (rolePermissions[role] as readonly string[]).includes(permission) ||
    (role === "staff" && permission === "view_audit_logs" && auditRead);
}
export class PermissionDeniedError extends Error {
  readonly code = "permission-denied";
  constructor(readonly reason = "Permission is required.") {
    super("You do not have permission to access this feature.");
  }
}
export function requirePermission(role: UserRole, permission: Permission, auditRead = false): void {
  if (!hasPermission(role, permission, auditRead)) throw new PermissionDeniedError();
}

export function canReadWorkflowRecord(actor: AuthenticatedUser,
  kind: "payments" | "tasks" | "messages" | "conversations", data: Record<string, unknown>): boolean {
  if (kind === "payments" && hasPermission(actor.role, "manage_business_settings")) return true;
  if (!hasPermission(actor.role, "view_own_workflow")) return false;
  switch (kind) {
    case "payments": return [data.recipient_id, data.customer_id, data.client_id].includes(actor.uid);
    case "tasks": return [data.assignee_id, data.recipient_id].includes(actor.uid);
    case "messages": return [data.sender_id, data.recipient_id].includes(actor.uid);
    case "conversations": return Array.isArray(data.participant_ids) && data.participant_ids.includes(actor.uid);
  }
}

/** Role requirements for protected actions implemented by the backend. */
export const protectedActionRoles = {
  listStaffAccounts: ["admin"], createStaffAccount: ["admin"], updateStaffAccount: ["admin"],
  setStaffAccountActive: ["admin"], readStaffAccountHistory: ["admin"],
  readAuditMetadata: ["admin"], verifyPayments: ["admin"],
  readOwnNotifications: userRoles,
  updateOwnNotifications: userRoles,
  createDietPlanAssignmentNotification: ["admin", "dietitian"],
  createTaskAssignmentNotification: ["admin", "dietitian"],
  createClientAssignmentNotification: ["admin"],
} as const satisfies Record<string, readonly UserRole[]>;

export type ProtectedAction = keyof typeof protectedActionRoles;

export function roleCanPerformAction(
  role: UserRole,
  action: ProtectedAction,
): boolean {
  return (protectedActionRoles[action] as readonly UserRole[]).includes(role);
}
