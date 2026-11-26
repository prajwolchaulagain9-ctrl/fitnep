import { Permission } from "./authorization_policy";
export interface EndpointAccess { permission: Permission; resource: string; recordId?: string; }
const resources: Partial<Record<Permission, string>> = {
  view_dashboard: "account_session", view_own_profile: "own_profile", edit_own_profile: "own_profile",
  manage_user_roles: "admin_user_management", manage_client_accounts: "client_account_management",
  manage_client_assignments: "client_assignments", view_audit_logs: "authorization_audit",
  view_assigned_clients: "assigned_client_profiles", view_client_records: "private_client_records",
  view_own_client_records: "own_client_intake",
  view_assigned_client_records: "assigned_client_intakes",
  collect_own_records: "own_client_records", view_own_diet_plans: "client_diet_plans",
  manage_diet_plans: "assigned_client_diet_plans", view_own_notifications: "own_notifications",
  update_own_notifications: "own_notifications", manage_own_privacy: "privacy_preferences",
  view_packages: "package_catalog", manage_business_settings: "business_management",
  manage_own_membership: "own_membership", view_own_workflow: "workflow_records",
};
const endpoints: [string, RegExp, Permission][] = [
  ["GET", /^\/session$/, "view_dashboard"],
  ["POST", /^\/authorization\/check$/, "view_dashboard"],
  ["POST", /^\/auth\/staff\/change-temporary-password$/, "edit_own_profile"],
  ["POST", /^\/auth\/google\/email-password$/, "edit_own_profile"],
  ["GET", /^\/admin\/staff-accounts(?:\/history)?$/, "manage_staff_accounts"],
  ["POST", /^\/admin\/staff-accounts$/, "manage_staff_accounts"],
  ["PATCH", /^\/admin\/staff-accounts\/([^/]+)(?:\/active)?$/, "manage_staff_accounts"],
  ["GET", /^\/profile\/me$/, "view_own_profile"],
  ["PATCH", /^\/profile\/me$/, "edit_own_profile"],
  ["GET", /^\/admin\/users$/, "manage_user_roles"],
  ["GET", /^\/admin\/users\/([^/]+)$/, "manage_user_roles"],
  ["PATCH", /^\/admin\/users\/([^/]+)$/, "manage_user_roles"],
  ["GET", /^\/admin\/clients(?:\/([^/]+))?$/, "manage_client_accounts"],
  ["PATCH", /^\/admin\/clients\/([^/]+)\/status$/, "manage_client_accounts"],
  ["PUT", /^\/admin\/clients\/([^/]+)\/assignment$/, "manage_client_assignments"],
  ["GET", /^\/admin\/clients\/([^/]+)\/assignment$/, "manage_client_assignments"],
  ["GET", /^\/admin\/audit-logs$/, "view_audit_logs"],
  ["GET", /^\/clients\/assigned$/, "view_assigned_clients"],
  ["GET", /^\/clients\/([^/]+)\/profile$/, "view_assigned_clients"],
  ["GET", /^\/clients\/([^/]+)\/diet-plans$/, "view_own_diet_plans"],
  ["POST", /^\/clients\/([^/]+)\/diet-plans$/, "manage_diet_plans"],
  ["PATCH", /^\/clients\/([^/]+)\/diet-plans\/([^/]+)$/, "manage_diet_plans"],
  ["GET", /^\/clients\/([^/]+)\/records\/[^/]+(?:\/([^/]+)(?:\/photo)?)?$/, "view_client_records"],
  ["GET", /^\/admin\/client-assignments\/dietitian-counts$/, "manage_client_assignments"],
  ["GET", /^\/admin\/client-assignments\/([^/]+)\/eligibility$/, "manage_client_assignments"],
  ["PUT", /^\/admin\/client-assignments\/([^/]+)$/, "manage_client_assignments"],
  ["GET", /^\/dietitian\/assigned-clients\/([^/]+)$/, "view_assigned_clients"],
  ["GET", /^\/dietitian\/assigned-clients\/([^/]+)\/intake$/, "view_assigned_client_records"],
  ["PATCH", /^\/dietitian\/assigned-clients\/([^/]+)\/intake\/review$/, "view_assigned_client_records"],
  ["POST", /^\/clients\/([^/]+)\/records\/[^/]+$/, "collect_own_records"],
  ["GET", /^\/notifications(?:\/([^/]+))?$/, "view_own_notifications"],
  ["PATCH", /^\/notifications\/(read-all|([^/]+)\/read)$/, "update_own_notifications"],
  ["GET", /^\/privacy\/preferences$/, "manage_own_privacy"],
  ["GET", /^\/intakes\/me$/, "view_client_records"],
  ["GET", /^\/intakes\/me\/draft$/, "view_own_client_records"],
  ["PUT", /^\/intakes\/me\/draft$/, "view_own_client_records"],
  ["POST", /^\/intakes\/me\/submit$/, "view_own_client_records"],
  ["GET", /^\/clients\/([^/]+)\/intake(?:\/versions\/[^/]+)?$/, "view_client_records"],
  ["PATCH", /^\/privacy\/preferences$/, "manage_own_privacy"],
  ["GET", /^\/packages$/, "view_packages"],
  ["GET", /^\/admin\/(?:packages|package-history|memberships\/pending)$/, "manage_business_settings"],
  ["POST", /^\/admin\/memberships\/([^/]+)\/verify-payment$/, "manage_business_settings"],
  ["POST", /^\/packages$/, "manage_business_settings"],
  ["PATCH", /^\/packages\/([^/]+)(?:\/active)?$/, "manage_business_settings"],
  ["GET", /^\/(?:memberships\/me|purchases\/current)$/, "manage_own_membership"],
  ["POST", /^\/(?:memberships|purchases)$/, "manage_own_membership"],
  ["GET", /^\/(diet-plans|conversations|messages|tasks|payments)\/([^/]+)$/, "view_own_workflow"],
];
// Express routes are case-insensitive, accept one trailing slash, and use GET
// handlers for HEAD. Match those semantics without changing record-ID casing.
const expressEndpoints = endpoints.map(([verb, expression, permission]) =>
  [verb, new RegExp(expression.source, "i"), permission] as const);

export function endpointAccess(method: string, path: string): EndpointAccess | null {
  const requestMethod = method === "HEAD" ? "GET" : method;
  const requestPath = path.endsWith("/") ? path.slice(0, -1) : path;
  for (const [verb, expression, permission] of expressEndpoints) {
    const match = expression.exec(requestPath);
    if (requestMethod === verb && match) {
      return { permission, resource: resources[permission] ?? "protected_feature",
        recordId: match.slice(1).reverse().find(value => value !== undefined) };
    }
  }
  return null;
}
