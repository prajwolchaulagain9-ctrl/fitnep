import { Router, Request, Response, NextFunction } from "express";
import { FieldPath, FieldValue, Timestamp, Transaction } from "firebase-admin/firestore";
import { PrivateRecordsStore } from "./private_records";
import { HealthReadTarget, healthAuditTarget } from "./audited_health_reads";
import { AuthenticatedUser, isUserRole } from "./domain";
import { Account, AccountInputError, FirestoreAccountService, FirestoreAuditStore, identifier, accountFrom,
  getCurrentAssignment, sessionPayload } from "./account_service";
import { canReadWorkflowRecord, permissions, PermissionDeniedError, requirePermission } from "./authorization_policy";
import { endpointAccess } from "./endpoint_access";
import { listAuditEvents } from "./audit_reader";

export class BackendUnavailableError extends Error {}
export function createRbacRouter(accounts?: FirestoreAccountService, audit?: FirestoreAuditStore, healthReads?: PrivateRecordsStore): Router {
  const router = Router();
  const store = () => { if (!accounts) throw new BackendUnavailableError(); return accounts; };
  const actor = (response: Response) => response.locals.user as AuthenticatedUser;
  const body = (request: Request): Record<string, unknown> => {
    if (!request.body || typeof request.body !== "object" || Array.isArray(request.body)) throw new AccountInputError("Invalid request.");
    return request.body;
  };
  const cursor = (request: Request) => request.query.after === undefined ? undefined : identifier(request.query.after);
  const page = (items: { id: string }[]) => items.length === 50 ? items.at(-1)!.id : null;
  const health = () => { if (!healthReads) throw new BackendUnavailableError(); return healthReads; };
  const readHealth = <T>(response: Response, target: HealthReadTarget,
    load: (transaction: Transaction) => Promise<{ data: T; recordIds?: readonly string[] }>) => {
    response.locals.healthAuditTarget = healthAuditTarget(target);
    return health().readResource(actor(response), target, load, response.locals.correlationId);
  };
  router.get("/session", wrap(async (_request, response) => {
    response.json({ data: { ...sessionPayload(await store().get(actor(response).uid)),
      must_change_password: actor(response).mustChangePassword === true } });
  }));
  router.post("/authorization/check", wrap(async (request, response) => {
    const submitted = body(request);
    if (typeof submitted.permission !== "string" || !permissions.includes(submitted.permission as typeof permissions[number])) {
      throw new AccountInputError("Unknown permission.");
    }
    response.locals.access = { permission: submitted.permission, resource: "feature:" + submitted.permission };
    const user = actor(response);
    requirePermission(user.role, submitted.permission as typeof permissions[number], user.permissions?.auditRead);
    response.json({ data: { allowed: true } });
  }));
  router.get("/profile/me", wrap(async (_request, response) => {
    response.json({ data: { account: await store().get(actor(response).uid) } });
  }));
  router.patch("/profile/me", wrap(async (request, response) => {
    if (["role", "permissions", "account_status"].some(key => Object.hasOwn(body(request), key))) {
      response.locals.access = { permission: "manage_user_roles", resource: "own_account_permissions", recordId: actor(response).uid };
    }
    response.json({ data: { account: await store().editOwnProfile(actor(response), body(request)) } });
  }));
  router.get("/admin/users", wrap(async (request, response) => {
    const role = request.query.role;
    if (role !== undefined && !isUserRole(role)) throw new AccountInputError("Invalid role filter.");
    const users = await store().list(cursor(request), role);
    response.json({ data: { users, next_cursor: page(users) } });
  }));
  router.get("/admin/users/:id", wrap(async (request, response) => {
    response.json({ data: { account: await store().get(identifier(request.params.id)) } });
  }));
  router.patch("/admin/users/:id", wrap(async (request, response) => {
    response.json({ data: { account: await store().change(actor(response), identifier(request.params.id), body(request)) } });
  }));
  router.get("/admin/clients", wrap(async (request, response) => {
    const clients = await store().list(cursor(request), "client");
    response.json({ data: { clients: await Promise.all(clients.map(client => clientView(store(), client))), next_cursor: page(clients) } });
  }));
  router.get("/admin/clients/:id", wrap(async (request, response) => {
    const client = await store().get(identifier(request.params.id));
    if (client.role !== "client") throw new AccountInputError("Client account not found.");
    response.json({ data: { client: await clientView(store(), client) } });
  }));
  router.patch("/admin/clients/:id/status", wrap(async (request, response) => {
    const id = identifier(request.params.id);
    if ((await store().get(id)).role !== "client") throw new PermissionDeniedError();
    response.json({ data: { account: await store().change(actor(response), id, body(request)) } });
  }));
  router.put("/admin/clients/:id/assignment", wrap(async (request, response) => {
    await store().assign(actor(response), identifier(request.params.id), body(request));
    response.json({ data: { saved: true } });
  }));
  router.get("/admin/clients/:id/assignment", wrap(async (request, response) => {
    const id = identifier(request.params.id);
    const assignment = (await store().firestore.collection("client_assignments").doc(id).get()).data();
    response.json({ data: { assignment: assignment ? {
      dietitian_id: assignment.dietitian_id ?? null, staff_ids: assignment.staff_ids ?? [],
    } : null } });
  }));
  router.get("/admin/audit-logs", wrap(async (request, response) => {
    requirePermission(actor(response).role, "view_audit_logs");
    if (!audit) throw new BackendUnavailableError();
    const logs = await audit.list(cursor(request), request.query.record_id === undefined ? undefined : identifier(request.query.record_id));
    response.json({ data: { logs, next_cursor: page(logs) } });
  }));
  router.get("/admin/audit-events", wrap(async (request, response) => {
    if (!audit) throw new BackendUnavailableError();
    const events = await listAuditEvents(audit.firestore, request.query);
    response.set("Cache-Control", "no-store").json({ data: events });
  }));
  router.get("/clients/assigned", wrap(async (request, response) => {
    response.json({ data: await store().assigned(actor(response), cursor(request)) });
  }));
  router.get("/clients/:id/profile", wrap(async (request, response) => {
    const user = actor(response); const id = identifier(request.params.id);
    await store().assertAssigned(user, id);
    const client = await store().get(id);
    if (client.role !== "client" || client.account_status !== "active") throw new PermissionDeniedError();
    response.json({ data: { client: { id, full_name: client.full_name, email: client.email } } });
  }));
  router.get("/clients/:id/diet-plans", wrap(async (request, response) => {
    const id = identifier(request.params.id);
    const after = cursor(request);
    const data = await readHealth(response, { clientId: id, category: "diet-plans" }, async transaction => {
      let query = store().firestore.collection("diet_plans").where("client_id", "==", id).orderBy(FieldPath.documentId());
      if (after) query = query.startAfter(after);
      const rows = await transaction.get(query.limit(50));
      return { data: { plans: rows.docs.map(doc => publicPlan(doc.id, doc.data())),
        next_cursor: rows.size === 50 ? rows.docs.at(-1)!.id : null }, recordIds: rows.docs.map(doc => doc.id) };
    });
    response.json({ data });
  }));
  const savePlan = async (request: Request, response: Response) => {
    const user = actor(response); const clientId = identifier(request.params.id);
    const submitted = body(request);
    if (Object.keys(submitted).some(key => !["title", "description"].includes(key)) ||
        typeof submitted.title !== "string" || !submitted.title.trim() || submitted.title.length > 120 ||
        typeof submitted.description !== "string" || !submitted.description.trim() || submitted.description.length > 10000) {
      throw new AccountInputError("Supply a title and a diet plan description.");
    }
    const db = store().firestore;
    const reference = request.params.planId ? db.collection("diet_plans").doc(identifier(request.params.planId)) : db.collection("diet_plans").doc();
    await db.runTransaction(async transaction => {
      const latest = accountFrom(user.uid, (await transaction.get(db.collection("users").doc(user.uid))).data());
      requirePermission(latest.role, "manage_diet_plans");
      if (latest.account_status !== "active") throw new PermissionDeniedError();
      await store().assertAssigned({ ...user, role: latest.role, roleRevision: latest.role_revision }, clientId, transaction);
      const client = accountFrom(clientId, (await transaction.get(db.collection("users").doc(clientId))).data());
      if (client.role !== "client" || client.account_status !== "active") throw new PermissionDeniedError();
      const current = await transaction.get(reference);
      if (request.params.planId && (!current.exists || current.get("client_id") !== clientId)) throw new PermissionDeniedError();
      const fields = { client_id: clientId, title: submitted.title!.toString().trim(),
        description: submitted.description!.toString().trim(), assigned_by_id: user.uid,
        assigned_by_role: latest.role, dietitian_name: latest.full_name, updated_at: FieldValue.serverTimestamp() };
      if (current.exists) transaction.update(reference, fields);
      else transaction.create(reference, { ...fields, created_at: FieldValue.serverTimestamp() });
    });
    response.status(request.params.planId ? 200 : 201).json({ data: { plan: publicPlan(reference.id, (await reference.get()).data()!) } });
  };
  router.post("/clients/:id/diet-plans", wrap(savePlan));
  router.patch("/clients/:id/diet-plans/:planId", wrap(savePlan));
  router.get("/diet-plans/:id", wrap(async (request, response) => {
    const doc = await store().firestore.collection("diet_plans").doc(identifier(request.params.id)).get();
    if (!doc.exists) throw new PermissionDeniedError("The requested plan is unavailable to this account.");
    const clientId = identifier(doc.get("client_id"));
    const plan = await readHealth(response, { clientId, category: "diet-plans", recordId: doc.id }, async transaction => {
      const current = await transaction.get(doc.ref);
      if (!current.exists || current.get("client_id") !== clientId) throw new PermissionDeniedError();
      return { data: publicPlan(current.id, current.data()!) };
    });
    response.json({ data: { diet_plan: plan } });
  }));
  const messageClient = async (data: Record<string, unknown>, transaction?: Transaction): Promise<string> => {
    if (data.client_id !== undefined) return identifier(data.client_id);
    const participants = [...new Set(Array.isArray(data.participant_ids) ? data.participant_ids : [data.sender_id, data.recipient_id])]
      .filter(value => value !== undefined).map(identifier);
    const clients: string[] = [];
    for (const id of participants) {
      const reference = store().firestore.collection("users").doc(id);
      const account = accountFrom(id, (transaction ? await transaction.get(reference) : await reference.get()).data());
      if (account.role === "client") clients.push(id);
    }
    if (clients.length !== 1) throw new PermissionDeniedError("The conversation has no unambiguous client owner.");
    return clients[0]!;
  };
  for (const [path, collection, key] of [
    ["tasks", "tasks", "task"], ["payments", "payments", "payment"],
    ["conversations", "conversations", "conversation"], ["messages", "messages", "message"],
  ]) {
    router.get("/" + path + "/:id", wrap(async (request, response) => {
      const user = actor(response);
      const doc = await store().firestore.collection(collection!).doc(identifier(request.params.id)).get();
      const data = doc.data();
      if (!data || !canReadWorkflowRecord(user, path as "payments" | "tasks" | "messages" | "conversations", data)) {
        throw new PermissionDeniedError("The record is outside this account.");
      }
      const project = (record: Record<string, unknown>) => {
        const safe: Record<string, unknown> = { id: doc.id };
        for (const field of ["title", "description", "body", "message", "last_message", "sender_name",
          "status", "priority", "due_at", "created_at", "sent_at", "amount", "amount_npr", "currency", "payment_method", "paid_at"]) {
          if (record[field] !== undefined) safe[field] = record[field] instanceof Timestamp ? record[field].toDate().toISOString() : record[field];
        }
        return safe;
      };
      const clinical = path === "messages" || path === "conversations";
      let safe = clinical ? undefined : project(data);
      if (clinical) {
        const clientId = await messageClient(data);
        safe = await readHealth(response, { clientId, category: "messages", recordId: doc.id }, async transaction => {
          const current = (await transaction.get(doc.ref)).data();
          if (!current || !canReadWorkflowRecord(user, path as "messages" | "conversations", current) ||
            await messageClient(current, transaction) !== clientId) throw new PermissionDeniedError();
          return { data: project(current) };
        });
      }
      response.json({ data: { [key!]: safe } });
    }));
  }
  return router;
}
function wrap(fn: (request: Request, response: Response) => Promise<void>) {
  return (request: Request, response: Response, next: NextFunction) => {
    void (async () => {
      // The registered route is server-owned. Recheck its policy even if an
      // incoming URL alias was missed by the app-level permission middleware.
      const access = endpointAccess(request.method, request.route.path);
      if (!access) throw new PermissionDeniedError("The endpoint has no authorization policy.");
      const user = response.locals.user as AuthenticatedUser;
      requirePermission(user.role, access.permission, user.permissions?.auditRead);
      await fn(request, response);
    })().catch(next);
  };
}
function publicPlan(id: string, data: Record<string, unknown>) {
  return { id, title: data.title, description: data.description, dietitian_name: data.dietitian_name,
    created_at: data.created_at instanceof Timestamp ? data.created_at.toDate().toISOString() : null };
}
async function clientView(store: FirestoreAccountService, account: Account) {
  // Optional existing business profile fields remain separate from identity/roles.
  const profile = (await store.firestore.collection("client_profiles").doc(account.id).get()).data() ?? {};
  const assignment = await getCurrentAssignment(store.firestore, account.id);
  const businessProfile: Record<string, unknown> = {};
  for (const field of ["phone", "gender", "dateOfBirth", "address", "packageId", "packageName",
    "deactivatedAt", "deactivationReason", "totalAmountPaid", "outstandingAmount",
    "lastPaymentDate", "paymentHistory", "packageHistory"]) {
    if (profile[field] !== undefined) businessProfile[field] =
      profile[field] instanceof Timestamp ? profile[field].toDate().toISOString() : profile[field];
  }
  return { ...businessProfile, id: account.id, name: account.full_name, email: account.email,
    status: account.account_status, joinDate: account.created_at,
    deactivatedAt: account.deactivated_at, deactivationReason: account.deactivation_reason,
    assignedDietitianId: assignment?.team.dietitianId ?? "",
    assignedDietitianName: assignment ? (await store.get(assignment.team.dietitianId)).full_name : "" };
}
