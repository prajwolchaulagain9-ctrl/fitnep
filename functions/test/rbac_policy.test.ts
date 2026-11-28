import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { it } from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import express, { Request, Response, NextFunction } from "express";
import request from "supertest";
import { accountFrom } from "../src/account_service";
import { canReadWorkflowRecord, hasPermission, PermissionDeniedError, rolePermissions } from "../src/authorization_policy";
import { userRoles } from "../src/domain";
import { endpointAccess } from "../src/endpoint_access";
import { createRbacRouter } from "../src/rbac_http";
import { createNotificationApp } from "../src/http_app";
import { UnconfiguredNotificationRepository } from "../src/notification_repository";

it("each of the four roles has a distinct dashboard and least-privilege permissions", () => {
  assert.deepEqual([...userRoles].sort(), ["admin", "client", "dietitian", "staff"]);
  for (const role of userRoles) {
    assert(hasPermission(role, "view_" + role + "_dashboard"));
    assert(hasPermission(role, "view_own_profile"));
    assert.equal(hasPermission(role, "manage_user_roles"), role === "admin");
    assert.equal(hasPermission(role, "manage_diet_plans"), role === "dietitian");
    assert.equal(hasPermission(role, "unknown_permission"), false);
  }
  assert.equal(hasPermission("staff", "view_client_records"), true);
});
it("Flutter and backend permission maps agree", () => {
  const dart = readFileSync("../lib/shared/role_permissions.dart", "utf8");
  const quoted = (text: string) => [...text.matchAll(/'([a-z_]+)'/g)].map(match => match[1]!);
  const own = quoted(/static const own = \{([\s\S]*?)\};/.exec(dart)![1]!);
  for (const role of userRoles) {
    const section = new RegExp("FitNepRole\\." + role + ": \\{([\\s\\S]*?)\\}").exec(dart)![1]!;
    assert.deepEqual([...new Set([...own, ...quoted(section)])].sort(), [...new Set(rolePermissions[role])].sort());
  }
});
it("active account records reject missing, empty, multiple, invalid and malformed roles", () => {
  const fields = { full_name: "Client", email: "client@example.test", role: "client",
    account_status: "active", created_at: Timestamp.now(), updated_at: Timestamp.now() };
  for (const role of [null, undefined, "", "CEO", "owner", ["client", "admin"]]) {
    assert.throws(() => accountFrom("user-1", { ...fields, role }), PermissionDeniedError);
  }
  for (const role of userRoles) assert.equal(accountFrom("user-1", { ...fields, role }).role, role);
  assert.throws(() => accountFrom("user-1", { ...fields, account_status: "pending" }), PermissionDeniedError);
});
it("existing and new protected endpoints have centralized permissions", () => {
  for (const [method, path] of [["GET", "/admin/users"], ["PATCH", "/admin/users/client"],
    ["GET", "/admin/audit-logs"], ["PUT", "/admin/clients/client/assignment"],
    ["POST", "/clients/client/diet-plans"], ["GET", "/clients/client/records/nutrition-records"],
    ["GET", "/dietitian/assigned-clients/client/intake"],
    ["PATCH", "/dietitian/assigned-clients/client/intake/review"],
    ["PATCH", "/notifications/id/read"], ["GET", "/purchases/current"], ["GET", "/conversations/id"]]) {
    assert(endpointAccess(method!, path!), path);
  }
});
it("permission matching follows Express aliases and preserves record-ID casing", () => {
  const expected = endpointAccess("GET", "/admin/users/MixedCase_UID");
  assert.equal(expected?.recordId, "MixedCase_UID");
  for (const path of ["/ADMIN/USERS/MixedCase_UID", "/Admin/Users/MixedCase_UID/"]) {
    assert.deepEqual(endpointAccess("GET", path), expected);
    assert.deepEqual(endpointAccess("HEAD", path), expected);
  }
  assert.equal(endpointAccess("GET", "/admin/users/MixedCase_UID//"), null);
  assert.equal(endpointAccess("POST", "/admin/users"), null);
  assert.equal(endpointAccess("HEAD", "/authorization/check"), null);
  assert.equal(endpointAccess("POST", "/AUTHORIZATION/CHECK/")?.permission, "view_dashboard");
});
it("every registered backend route has a policy, including implicit HEAD handlers", () => {
  const app = createNotificationApp({
    authVerifier: { async verifyIdToken() { throw new Error("This test never authenticates a request."); } },
    notificationRepository: new UnconfiguredNotificationRepository(),
  });
  type Layer = { route?: { path: string; methods: Record<string, boolean> }; handle?: { stack?: Layer[] } };
  let checked = 0;
  const inspect = (layers: Layer[]) => {
    for (const layer of layers) {
      if (layer.route) {
        for (const method of Object.keys(layer.route.methods)) {
          assert(endpointAccess(method.toUpperCase(), layer.route.path), `${method} ${layer.route.path}`);
          if (method === "get") assert(endpointAccess("HEAD", layer.route.path), layer.route.path);
          checked++;
        }
      } else if (layer.handle?.stack) inspect(layer.handle.stack);
    }
  };
  inspect(app._router.stack as Layer[]);
  assert(checked > 30, "Inspect both legacy APIs and the RBAC router.");
});
it("an RBAC handler registered without a policy fails closed before accessing storage", async () => {
  const router = createRbacRouter();
  const usersRoute = router.stack.find((layer: { route?: { path: string } }) => layer.route?.path === "/admin/users");
  const usersHandler = usersRoute?.route?.stack[0]?.handle;
  assert(usersHandler);
  const app = express();
  // Reuse the real handler under an unconfigured server-side alias. There is
  // no auth fixture or account store to accidentally grant this request access.
  app.get("/unconfigured-rbac-route", usersHandler);
  app.use((error: unknown, _request: Request, response: Response, _next: NextFunction) => {
    response.status(error instanceof PermissionDeniedError ? 403 : 500).json({
      code: error instanceof PermissionDeniedError ? "permission-denied" : "unexpected-error",
    });
  });
  const denied = await request(app).get("/unconfigured-rbac-route");
  assert.equal(denied.status, 403);
  assert.equal(denied.body.code, "permission-denied");
});
it("record ownership uses the specific workflow schema without granting a sender access to others' financial data", () => {
  const staff = { uid: "staff", role: "staff" as const };
  const data = { sender_id: "staff", recipient_id: "client", assignee_id: "client", participant_ids: ["client", "other"] };
  assert.equal(canReadWorkflowRecord(staff, "payments", data), false);
  assert.equal(canReadWorkflowRecord(staff, "tasks", data), false);
  assert.equal(canReadWorkflowRecord(staff, "conversations", data), false);
  assert.equal(canReadWorkflowRecord(staff, "messages", data), true);
  assert.equal(canReadWorkflowRecord({ uid: "client", role: "client" }, "payments", data), true);
  assert.equal(canReadWorkflowRecord({ uid: "ceo", role: "admin" }, "payments", data), true);
});
