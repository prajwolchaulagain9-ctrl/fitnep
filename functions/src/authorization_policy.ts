import { UserRole } from "./domain";

/** Role requirements for protected actions implemented by the backend. */
export const protectedActionRoles = {
  readOwnNotifications: ["admin", "dietitian", "client"],
  updateOwnNotifications: ["admin", "dietitian", "client"],
  viewPackageCatalog: ["admin", "dietitian", "client"],
  listStaffAccounts: ["admin"],
  createStaffAccount: ["admin"],
  updateStaffAccount: ["admin"],
  setStaffAccountActive: ["admin"],
  readStaffAccountHistory: ["admin"],
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
