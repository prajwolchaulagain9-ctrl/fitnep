import { Router, Request, Response, NextFunction } from "express";
import { FieldPath, Timestamp, Transaction } from "firebase-admin/firestore";
import { PrivateRecordsError, PrivateRecordsStore } from "./private_records";
import { HealthReadTarget, healthAuditTarget } from "./audited_health_reads";
import { AuthenticatedUser, isUserRole } from "./domain";
import { Account, AccountInputError, FirestoreAccountService, FirestoreAuditStore, identifier, accountFrom,
  getCurrentAssignment, sessionPayload } from "./account_service";
import { canReadWorkflowRecord, permissions, PermissionDeniedError, requirePermission } from "./authorization_policy";
import { endpointAccess } from "./endpoint_access";
import { listAssignedDietitianClients } from "./assigned_clients";
import { listAuditEvents } from "./audit_reader";
import { onboarding, saveOnboarding } from "./onboarding";
import { publicDietPlan, writeDietPlan } from "./diet_plan_workflow";
import { FirestorePackageService, PackageError } from "./package_membership_service";
import type { CheckoutPayments } from "./checkout_payments";

export class BackendUnavailableError extends Error {}
export function createRbacRouter(accounts?: FirestoreAccountService, audit?: FirestoreAuditStore,
  healthReads?: PrivateRecordsStore, payments?: Pick<CheckoutPayments, "listClientPayments">): Router {
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
    requirePermission(user.role, submitted.permission as typeof permissions[number], user.permissions?.auditRead, user.permissions?.paymentsVerify);
    response.json({ data: { allowed: true } });
  }));
  router.get("/profile/me", wrap(async (_request, response) => {
    const user = actor(response);
    const account = await store().ownProfile(user);
    if (account.role !== "client") {
      response.json({ data: { account } });
      return;
    }
    const profile = await store().firestore.doc(`users/${user.uid}`).get();
    response.json({ data: { account, onboarding: onboarding(profile.get("onboarding")) } });
  }));
  router.put("/profile/me/onboarding", wrap(async (request, response) => {
    const value = await saveOnboarding(store().firestore, actor(response), body(request));
    response.json({ data: { onboarding: value } });
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
    response.json({ data: { client: await clientView(store(), client, payments) } });
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
    const db = store().firestore;
    const assignment = await db.runTransaction(async transaction => {
      const current = await getCurrentAssignment(db, id, transaction, { includeInactiveClient: true });
      if (current) return { dietitian_id: current.team.dietitianId, staff_ids: current.team.teamMemberIds };
      const cleared = (await transaction.get(db.doc(`client_assignments/${id}`))).data();
      return cleared?.active === false && cleared.dietitian_id === null
        ? { dietitian_id: null, staff_ids: cleared.staff_ids ?? [] }
        : null;
    });
    response.json({ data: { assignment } });
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
    const user = actor(response);
    const after = cursor(request);
    const data = user.role === "dietitian"
      ? await listAssignedDietitianClients(store().firestore, user, request.query, after, response.locals.correlationId)
      : await store().assigned(user, after);
    response.json({ data });
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
      const plans = rows.docs.flatMap(doc => {
        const plan = publicDietPlan(doc.id, doc.data(), actor(response).role === "client");
        return plan ? [plan] : [];
      });
      return { data: { plans, next_cursor: rows.size === 50 ? rows.docs.at(-1)!.id : null },
        recordIds: plans.map(plan => plan.id) };
    });
    response.json({ data });
  }));
  router.get("/clients/:id/weight-history", wrap(async (request, response) => {
    const clientId = identifier(request.params.id);
    const after = cursor(request);
    const data = await readHealth(response, { clientId, category: "weight-history" }, async transaction => {
      const versions = store().firestore.collection(`client_intakes/${clientId}/versions`);
      let query = versions.orderBy("submitted_at", "desc");
      if (after) {
        const previous = await transaction.get(versions.doc(after));
        if (!previous.exists || previous.get("client_id") !== clientId) {
          throw new PrivateRecordsError(400, "Invalid weight history cursor.");
        }
        query = query.startAfter(previous);
      }
      const rows = await transaction.get(query.limit(50));
      const records = rows.docs.flatMap(doc => {
        const weight = doc.get("health_information.weight_kg");
        const recordedAt = doc.get("submitted_at");
        return doc.get("client_id") === clientId && Number.isFinite(weight) && weight >= 1 && weight <= 500 &&
          recordedAt instanceof Timestamp
          ? [{ id: doc.id, details: { weight_kg: weight }, recorded_at: recordedAt.toDate().toISOString() }] : [];
      });
      return { data: { records, next_cursor: rows.size === 50 ? rows.docs.at(-1)!.id : null },
        recordIds: records.map(record => record.id) };
    });
    response.json({ data });
  }));
  const savePlan = async (request: Request, response: Response) => {
    const planId = request.params.planId === undefined ? undefined : identifier(request.params.planId);
    const plan = await writeDietPlan(store().firestore, actor(response), identifier(request.params.id), planId,
      body(request), response.locals.correlationId);
    response.status(planId ? 200 : 201).json({ data: { plan } });
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
      const visible = publicDietPlan(current.id, current.data()!, actor(response).role === "client");
      if (!visible) throw new PermissionDeniedError("The requested plan is unavailable to this account.");
      return { data: visible };
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
      requirePermission(user.role, access.permission, user.permissions?.auditRead, user.permissions?.paymentsVerify);
      await fn(request, response);
    })().catch(next);
  };
}
async function clientView(store: FirestoreAccountService, account: Account,
  payments?: Pick<CheckoutPayments, "listClientPayments">) {
  const db = store.firestore;
  const [profileSnapshot, assignment, memberships, receipts] = await Promise.all([
    db.doc(`client_profiles/${account.id}`).get(),
    getCurrentAssignment(db, account.id, undefined, { includeInactiveClient: true }),
    new FirestorePackageService(db).membershipsWithLegacy(account.id).catch(error => {
      if (error instanceof PackageError && error.statusCode === 503) return [];
      throw error;
    }),
    payments?.listClientPayments(account.id) ?? [],
  ]);
  const profile = profileSnapshot.data() ?? {};
  const businessProfile: Record<string, unknown> = {};
  for (const field of ["phone", "gender", "dateOfBirth", "address", "packageId", "packageName",
    "deactivatedAt", "deactivationReason", "totalAmountPaid", "outstandingAmount",
    "lastPaymentDate", "paymentHistory", "packageHistory"]) {
    if (profile[field] !== undefined) businessProfile[field] =
      profile[field] instanceof Timestamp ? profile[field].toDate().toISOString() : profile[field];
  }
  const current = memberships.find(member => member.status === "active") ??
    memberships.find(member => member.status === "scheduled") ??
    memberships.find(member => member.status === "pending");
  if (memberships.length) {
    businessProfile.packageId = current?.package.id ?? "";
    businessProfile.packageName = current?.package.name ?? "No current package";
    businessProfile.packageStatus = current?.status ?? "expired";
  }
  if (receipts.length) {
    const receiptIds = new Set(receipts.map(receipt => receipt.id));
    const legacy = Array.isArray(profile.paymentHistory) ? profile.paymentHistory : [];
    businessProfile.paymentHistory = [
      ...receipts.map(receipt => ({
        id: receipt.id, date: receipt.created_at, amount: receipt.amount_npr,
        status: receipt.status === "verified" ? "paid" : receipt.status, description: receipt.package.name,
      })),
      ...legacy.filter(entry => !receiptIds.has(entry?.id)),
    ];
  }
  if (payments && memberships.length) {
    const terms = memberships.flatMap(member => member.start_at && member.end_at ? [{
      packageId: member.package.id, packageName: member.package.name, startDate: member.start_at, endDate: member.end_at,
    }] : []);
    const legacy = Array.isArray(profile.packageHistory) ? profile.packageHistory : [];
    businessProfile.packageHistory = [
      ...terms,
      ...legacy.filter(entry => !terms.some(term => term.packageId === entry?.packageId && term.startDate === entry?.startDate)),
    ];
  }
  return { ...businessProfile, id: account.id, name: account.full_name, email: account.email,
    status: account.account_status, joinDate: account.created_at,
    deactivatedAt: account.deactivated_at, deactivationReason: account.deactivation_reason,
    assignedDietitianId: assignment?.team.dietitianId ?? "",
    assignedDietitianName: assignment ? assignment.dietitian.full_name || assignment.dietitian.email || assignment.dietitian.id : "" };
}
