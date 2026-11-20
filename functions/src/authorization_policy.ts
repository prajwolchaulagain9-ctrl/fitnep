import { UserRole, userRoles } from "./domain";

/** Role requirements for protected actions implemented by the backend. */
export const protectedActionRoles = {
  readOwnNotifications: userRoles,
  updateOwnNotifications: userRoles,
  createDietPlanAssignmentNotification: ["admin", "dietitian"],
  createTaskAssignmentNotification: ["admin", "dietitian"],
} as const satisfies Record<string, readonly UserRole[]>;

export type ProtectedAction = keyof typeof protectedActionRoles;

export function roleCanPerformAction(
  role: UserRole,
  action: ProtectedAction,
): boolean {
  return (protectedActionRoles[action] as readonly UserRole[]).includes(role);
}
