import { Auth, UserRecord } from "firebase-admin/auth";
import { FieldPath, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { AuthenticatedUser, isUserRole, UserRole } from "./domain";
import { Permission, PermissionDeniedError, rolePermissions, requirePermission } from "./authorization_policy";

export interface Account {
  id: string; full_name: string; email: string; role: UserRole; role_revision: number;
  account_status: "active" | "inactive"; created_at: string; updated_at: string;
  deactivated_at?: string | null; deactivation_reason?: string | null;
}
export class AccountInputError extends Error {}
export function identifier(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new AccountInputError("Invalid account identifier.");
  }
  return value;
}
export function accountFrom(id: string, data: Record<string, unknown> | undefined): Account {
  if (!data || !isUserRole(data.role) || !["active", "inactive"].includes(String(data.account_status)) ||
      !(data.created_at instanceof Timestamp) || !(data.updated_at instanceof Timestamp)) {
    throw new PermissionDeniedError("The account has no valid role or status.");
  }
  if (data.role_revision !== undefined && (!Number.isSafeInteger(data.role_revision) || (data.role_revision as number) < 0)) {
    throw new PermissionDeniedError("The account has no valid role revision.");
  }
  return { id, full_name: typeof data.full_name === "string" ? data.full_name : "",
    email: typeof data.email === "string" ? data.email : "", role: data.role,
    role_revision: typeof data.role_revision === "number" ? data.role_revision : 0,
    account_status: data.account_status as Account["account_status"],
    created_at: data.created_at.toDate().toISOString(), updated_at: data.updated_at.toDate().toISOString(),
    deactivated_at: data.deactivated_at instanceof Timestamp ? data.deactivated_at.toDate().toISOString() : null,
    deactivation_reason: typeof data.deactivation_reason === "string" ? data.deactivation_reason : null };
}
export interface DeniedAttempt {
  uid: string | null; role: UserRole | null; action: string; resource: string;
  recordId?: string | null; reason: string;
}
export class FirestoreAuditStore {
  constructor(readonly firestore: Firestore) {}
  async denied(attempt: DeniedAttempt): Promise<void> {
    const recordId = attempt.recordId;
    const safeRecordId = typeof recordId === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(recordId) &&
      !/^(xkeysib-|gh[pousr]_)/i.test(recordId) ? recordId : null;
    await this.firestore.collection("audit_logs").add({
      user_id: attempt.uid, current_role: attempt.role, action: attempt.action.slice(0, 100),
      resource: attempt.resource.slice(0, 200), record_id: safeRecordId,
      result: "DENIED", reason: attempt.reason.slice(0, 200), timestamp: FieldValue.serverTimestamp(),
    });
  }
  async list(after?: string, recordId?: string) {
    let query = this.firestore.collection("audit_logs").orderBy(FieldPath.documentId());
    if (recordId) query = query.where("record_id", "==", identifier(recordId));
    if (after) query = query.startAfter(identifier(after));
    const records = await query.limit(50).get();
    return records.docs.map(doc => ({ id: doc.id, ...doc.data(),
      timestamp: (doc.get("timestamp") as Timestamp).toDate().toISOString() }));
  }
}
export class FirestoreAccountService {
  constructor(readonly firestore: Firestore, readonly auth: Auth) {}
  // Current Admin-SDK identity claims are a one-time migration source ONLY.
  // Never bootstrap from token claims or from a client-supplied role.
  async provision(identity: UserRecord): Promise<Account> {
    return this.firestore.runTransaction(async transaction => {
      const reference = this.firestore.collection("users").doc(identifier(identity.uid));
      const current = await transaction.get(reference);
      if (current.exists) return accountFrom(current.id, current.data());
      const oldRole: unknown = identity.customClaims?.role;
      if (oldRole !== undefined && !isUserRole(oldRole)) {
        throw new PermissionDeniedError("An operator must repair this account's invalid legacy role.");
      }
      const timestamp = Timestamp.now();
      const data = { full_name: identity.displayName ?? "", email: identity.email ?? "",
        role: oldRole ?? "client", role_revision: 0,
        account_status: identity.disabled ? "inactive" : "active", created_at: timestamp, updated_at: timestamp };
      transaction.create(reference, data);
      transaction.set(this.firestore.collection("account_access").doc(identity.uid), {
        revision: 0, updated_at: timestamp,
      });
      return accountFrom(reference.id, data);
    });
  }
  async current(uid: string): Promise<Account> {
    const doc = await this.firestore.collection("users").doc(identifier(uid)).get();
    return doc.exists ? accountFrom(uid, doc.data()) : this.provision(await this.auth.getUser(uid));
  }
  async list(after?: string, role?: UserRole): Promise<Account[]> {
    let query = this.firestore.collection("users").orderBy(FieldPath.documentId());
    if (role) query = query.where("role", "==", role);
    if (after) query = query.startAfter(identifier(after));
    const result = await query.limit(50).get();
    return result.docs.map(doc => accountFrom(doc.id, doc.data()));
  }
  async get(id: string): Promise<Account> {
    const doc = await this.firestore.collection("users").doc(identifier(id)).get();
    if (!doc.exists) throw new AccountInputError("Account not found.");
    return accountFrom(doc.id, doc.data());
  }
  async editOwnProfile(actor: AuthenticatedUser, body: Record<string, unknown>) {
    requirePermission(actor.role, "edit_own_profile");
    if (Object.keys(body).some(key => ["role", "permissions", "account_status", "uid", "id"].includes(key))) {
      throw new PermissionDeniedError("An account cannot assign its own role or status.");
    }
    if (Object.keys(body).length !== 1 || typeof body.full_name !== "string" ||
        body.full_name.trim().length < 1 || body.full_name.trim().length > 120) {
      throw new AccountInputError("Supply a full name of 1 to 120 characters.");
    }
    await this.firestore.collection("users").doc(actor.uid).update({
      full_name: body.full_name.trim(), updated_at: FieldValue.serverTimestamp(),
    });
    return this.get(actor.uid);
  }
  async change(actor: AuthenticatedUser, uid: string, body: Record<string, unknown>): Promise<Account> {
    identifier(uid);
    if (actor.uid === uid) throw new PermissionDeniedError("Administrators cannot change their own role or status.");
    const isRole = Object.hasOwn(body, "role");
    if (Object.keys(body).some(key => ![isRole ? "role" : "account_status", "reason"].includes(key)) ||
        (!isRole && !Object.hasOwn(body, "account_status")) ||
        (body.reason !== undefined && (typeof body.reason !== "string" || body.reason.length > 200))) {
      throw new AccountInputError("Change one role or account status at a time.");
    }
    if (isRole ? !isUserRole(body.role) : !["active", "inactive"].includes(String(body.account_status))) {
      throw new AccountInputError("Supply one valid role or account status.");
    }
    await this.firestore.runTransaction(async transaction => {
      const adminRef = this.firestore.collection("users").doc(actor.uid);
      const targetRef = this.firestore.collection("users").doc(uid);
      const [adminDoc, targetDoc] = await Promise.all([transaction.get(adminRef), transaction.get(targetRef)]);
      const admin = accountFrom(adminDoc.id, adminDoc.data());
      const target = accountFrom(targetDoc.id, targetDoc.data());
      if (admin.account_status !== "active") throw new PermissionDeniedError("The actor account is inactive.");
      requirePermission(admin.role, isRole ? "manage_user_roles" : accountManagementPermission(target.role));
      const role = isRole ? body.role as UserRole : target.role;
      const status = isRole ? target.account_status : body.account_status as Account["account_status"];
      if (role === target.role && status === target.account_status) return;
      // Assignment versions prevent old team grants returning after a later promotion.
      transaction.update(targetRef, { role, account_status: status, role_revision: target.role_revision + 1,
        ...(!isRole ? { deactivated_at: status === "inactive" ? FieldValue.serverTimestamp() : FieldValue.delete(),
          deactivation_reason: status === "inactive" && typeof body.reason === "string" ? body.reason.trim() : FieldValue.delete() } : {}),
        updated_at: FieldValue.serverTimestamp() });
      transaction.set(this.firestore.collection("account_access").doc(uid), {
        revision: target.role_revision + 1, updated_at: FieldValue.serverTimestamp(),
      });
      transaction.create(this.firestore.collection("audit_logs").doc(), {
        user_id: actor.uid, current_role: admin.role, record_id: uid, resource: "user_management",
        action: isRole ? "manage_user_roles" : "change_account_status", result: "ALLOWED",
        previous_role: target.role, new_role: role, previous_status: target.account_status,
        new_status: status, timestamp: FieldValue.serverTimestamp(),
        reason: typeof body.reason === "string" ? body.reason.trim() : null,
      });
    });
    // Old ID tokens cannot retain privileges: requests always reread users/{uid}.
    return this.get(uid);
  }
  async assertAssigned(actor: AuthenticatedUser, clientId: string, transaction?: Transaction) {
    requirePermission(actor.role, "view_assigned_clients");
    const reference = this.firestore.collection("client_assignments").doc(identifier(clientId));
    const data = (transaction ? await transaction.get(reference) : await reference.get()).data();
    const revision = actor.roleRevision ?? 0;
    const permitted = data?.active === true && (actor.role === "dietitian" ?
      data.dietitian_id === actor.uid && (data.dietitian_role_revision ?? 0) === revision :
      actor.role === "staff" && Array.isArray(data.staff_ids) && data.staff_ids.includes(actor.uid) &&
        (data.staff_role_revisions?.[actor.uid] ?? 0) === revision);
    if (!permitted) throw new PermissionDeniedError("The client is outside the current assignment.");
    const clientRef = this.firestore.collection("users").doc(clientId);
    const client = accountFrom(clientId, (transaction ? await transaction.get(clientRef) : await clientRef.get()).data());
    if (client.role !== "client" || client.account_status !== "active") throw new PermissionDeniedError("The client account is not active.");
    if ((data!.client_role_revision ?? 0) !== client.role_revision) throw new PermissionDeniedError("The care assignment must be renewed after an account change.");
    return data!;
  }
  async assigned(actor: AuthenticatedUser, after?: string) {
    requirePermission(actor.role, "view_assigned_clients");
    let query = this.firestore.collection("client_assignments")
      .where(actor.role === "dietitian" ? "dietitian_id" : "staff_ids",
        actor.role === "dietitian" ? "==" : "array-contains", actor.uid).orderBy(FieldPath.documentId());
    if (after) query = query.startAfter(identifier(after));
    const rows = await query.limit(50).get();
    const result: { id: string; full_name: string; email: string }[] = [];
    for (const row of rows.docs) {
      try { await this.assertAssigned(actor, row.id); } catch (error) {
        if (error instanceof PermissionDeniedError) continue;
        throw error;
      }
      const client = await this.get(row.id);
      if (client.role === "client" && client.account_status === "active") {
        result.push({ id: client.id, full_name: client.full_name, email: client.email });
      }
    }
    return { clients: result, next_cursor: rows.size === 50 ? rows.docs.at(-1)!.id : null };
  }
  async assign(actor: AuthenticatedUser, clientId: string, body: Record<string, unknown>) {
    if (Object.keys(body).some(key => !["dietitian_id", "staff_ids"].includes(key)) ||
        !(body.dietitian_id === null || typeof body.dietitian_id === "string") ||
        !Array.isArray(body.staff_ids) || body.staff_ids.length > 10 ||
        !body.staff_ids.every(id => typeof id === "string")) {
      throw new AccountInputError("Supply a dietitian ID (or null) and up to ten staff IDs.");
    }
    const staff = [...new Set(body.staff_ids as string[])].map(identifier);
    const dietitian = body.dietitian_id === null ? null : identifier(body.dietitian_id);
    await this.firestore.runTransaction(async transaction => {
      const admin = accountFrom(actor.uid, (await transaction.get(this.firestore.collection("users").doc(actor.uid))).data());
      requirePermission(admin.role, "manage_client_assignments");
      if (admin.account_status !== "active") throw new PermissionDeniedError();
      const client = accountFrom(clientId, (await transaction.get(this.firestore.collection("users").doc(identifier(clientId)))).data());
      if (client.role !== "client" || client.account_status !== "active") throw new AccountInputError("An active client is required.");
      const revisions: Record<string, number> = {};
      for (const [id, role] of [...staff.map(id => [id, "staff"] as const), ...(dietitian ? [[dietitian, "dietitian"] as const] : [])]) {
        const account = accountFrom(id, (await transaction.get(this.firestore.collection("users").doc(id))).data());
        if (account.role !== role || account.account_status !== "active") throw new AccountInputError("Assignments require active accounts with the matching role.");
        revisions[id] = account.role_revision;
      }
      const ref = this.firestore.collection("client_assignments").doc(clientId);
      const before = (await transaction.get(ref)).data();
      transaction.set(ref, { active: true, dietitian_id: dietitian, staff_ids: staff,
        client_role_revision: client.role_revision,
        dietitian_role_revision: dietitian ? revisions[dietitian] : null,
        staff_role_revisions: Object.fromEntries(staff.map(id => [id, revisions[id]])),
        updated_at: FieldValue.serverTimestamp() });
      transaction.create(this.firestore.collection("audit_logs").doc(), {
        user_id: actor.uid, current_role: admin.role, record_id: clientId, action: "manage_client_assignments",
        resource: "client_assignments", result: "ALLOWED",
        previous_dietitian_id: before?.dietitian_id ?? null, new_dietitian_id: dietitian,
        previous_staff_ids: before?.staff_ids ?? [], new_staff_ids: staff, timestamp: FieldValue.serverTimestamp(),
      });
    });
  }
}
export function accountManagementPermission(role: UserRole): Permission {
  return role === "staff" ? "manage_staff_accounts" : role === "dietitian" ?
    "manage_dietitian_accounts" : role === "admin" ? "manage_user_roles" : "manage_client_accounts";
}
export function sessionPayload(account: Account) {
  return { account, permissions: [...rolePermissions[account.role]] };
}
