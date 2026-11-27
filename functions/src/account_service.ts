import { Auth, UserRecord } from "firebase-admin/auth";
import { randomUUID } from "node:crypto";
import { FirestoreAuditWriter } from "./audit";
import { FieldPath, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { AuthenticatedUser, isUserRole, UserRole } from "./domain";
import { Permission, PermissionDeniedError, rolePermissions, requirePermission } from "./authorization_policy";
import { currentAssignedTeam } from "./nutrition_record_access_service";
import { FirestorePackageService, inactivePackageAssignmentMessage, PackageError } from "./package_membership_service";
import { intakeAge, isObject } from "./client_intake_answers";
import { hasValidPrivacyAcceptance } from "./privacy_policy_acceptance";

export interface Account {
  id: string; full_name: string; email: string; role: UserRole; role_revision: number;
  account_status: "active" | "inactive"; created_at: string; updated_at: string;
  deactivated_at?: string | null; deactivation_reason?: string | null;
  audit_read?: true;
}
export class AccountInputError extends Error {}

export const clientProfileFields = ["date_of_birth", "contact_email", "contact_phone"] as const;

export function legacyProfileDetails(
  account: Record<string, unknown>, draftAnswers: unknown, submittedAnswers: unknown,
): Partial<Record<typeof clientProfileFields[number], string>> {
  const draft = isObject(draftAnswers) ? draftAnswers : {};
  const submitted = isObject(submittedAnswers) ? submittedAnswers : {};
  const details: Partial<Record<typeof clientProfileFields[number], string>> = {};
  for (const field of clientProfileFields) {
    if (Object.hasOwn(account, field)) continue;
    const value = draft[field] ?? submitted[field];
    if (typeof value === "string" && value.trim()) details[field] = value.trim();
  }
  return details;
}
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
        ...(data.role === "staff" && (data.permissions as { audit_read?: unknown } | undefined)?.audit_read === true
          ? { audit_read: true as const } : {}),
    role_revision: typeof data.role_revision === "number" ? data.role_revision : 0,
    account_status: data.account_status as Account["account_status"],
    created_at: data.created_at.toDate().toISOString(), updated_at: data.updated_at.toDate().toISOString(),
    deactivated_at: data.deactivated_at instanceof Timestamp ? data.deactivated_at.toDate().toISOString() : null,
    deactivation_reason: typeof data.deactivation_reason === "string" ? data.deactivation_reason : null };
}
export function accountMatchesActor(account: Account, actor: AuthenticatedUser): boolean {
  return account.id === actor.uid && account.role === actor.role && account.account_status === "active" &&
    account.role_revision === (actor.roleRevision ?? 0);
}

/** Reuse current account revisions across private records, directories and counts. */
export async function getCurrentAssignment(firestore: Firestore, clientId: string, transaction?: Transaction) {
  const read = (reference: FirebaseFirestore.DocumentReference) => transaction ? transaction.get(reference) : reference.get();
  const data = (await read(firestore.collection("client_assignments").doc(identifier(clientId)))).data();
  const team = currentAssignedTeam(data);
  if (!team || (data!.client_id !== undefined && data!.client_id !== clientId)) return null;
  try {
    const [client, dietitian] = await Promise.all([
      read(firestore.collection("users").doc(clientId)),
      read(firestore.collection("users").doc(identifier(team.dietitianId))),
    ]);
    const clientAccount = accountFrom(clientId, client.data());
    const dietitianAccount = accountFrom(team.dietitianId, dietitian.data());
    if (clientAccount.role !== "client" || clientAccount.account_status !== "active" ||
        dietitianAccount.role !== "dietitian" || dietitianAccount.account_status !== "active" ||
        (data!.client_role_revision ?? 0) !== clientAccount.role_revision ||
        (data!.dietitian_role_revision ?? 0) !== dietitianAccount.role_revision) return null;
    return { data: data!, team, client: clientAccount, lastActivityAt: client.get("last_activity_at") };
  } catch (error) {
    if (error instanceof PermissionDeniedError || error instanceof AccountInputError) return null;
    throw error;
  }
}

export function assignmentIncludesActor(actor: AuthenticatedUser,
  assignment: NonNullable<Awaited<ReturnType<typeof getCurrentAssignment>>>): boolean {
  const { data, team } = assignment;
  if (actor.role === "dietitian") {
    return team.dietitianId === actor.uid && (data.dietitian_role_revision ?? 0) === (actor.roleRevision ?? 0);
  }
  const revisions = data.team_member_role_revisions === undefined ? data.staff_role_revisions : data.team_member_role_revisions;
  return (actor.role === "staff" || actor.role === "admin") && team.teamMemberIds.includes(actor.uid) &&
    (revisions?.[actor.uid] ?? 0) === (actor.roleRevision ?? 0);
}
export interface DeniedAttempt {
  uid: string | null; role: UserRole | null; action: string; resource: string;
  recordId?: string | null; reason: string;
}
export class FirestoreAuditStore {
  constructor(readonly firestore: Firestore) {}
  async denied(attempt: DeniedAttempt, appendUnified = true): Promise<void> {
    const recordId = attempt.recordId;
    const safeRecordId = typeof recordId === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(recordId) &&
      !/^(xkeysib-|gh[pousr]_)/i.test(recordId) ? recordId : null;
    await this.firestore.runTransaction(async transaction => {
      transaction.create(this.firestore.collection("audit_logs").doc(), {
      user_id: attempt.uid, current_role: attempt.role, action: attempt.action.slice(0, 100),
      resource: attempt.resource.slice(0, 200), record_id: safeRecordId,
      result: "DENIED", reason: attempt.reason.slice(0, 200), timestamp: FieldValue.serverTimestamp(),
      });
      if (appendUnified && attempt.uid && isUserRole(attempt.role)) new FirestoreAuditWriter(this.firestore).appendInTransaction(transaction, {
        actor: { uid: attempt.uid, role: attempt.role }, action: "access.denied", outcome: "denied",
        targetType: "api", targetId: safeRecordId ?? attempt.resource.slice(0, 200), correlationId: randomUUID(),
      });
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
      new FirestoreAuditWriter(this.firestore).appendInTransaction(transaction, {
        actor: { uid: identity.uid, role: data.role as UserRole, displayName: identity.displayName ?? identity.uid },
        action: "account.created", targetType: "account", targetId: identity.uid,
        status: data.account_status, outcome: "succeeded", correlationId: randomUUID(),
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
  async ownProfile(actor: AuthenticatedUser) {
    return this.firestore.runTransaction(async transaction => {
      const reference = this.firestore.doc(`users/${actor.uid}`);
      const data = (await transaction.get(reference)).data()!;
      const account = accountFrom(actor.uid, data);
      if (!accountMatchesActor(account, actor)) throw new PermissionDeniedError();
      if (account.role !== "client") return account;
      const intake = this.firestore.doc(`client_intakes/${actor.uid}`);
      const [draft, submitted, acceptance] = await Promise.all([
        transaction.get(intake.collection("private").doc("draft")), transaction.get(intake),
        transaction.get(this.firestore.doc(`privacy_acceptances/${actor.uid}`)),
      ]);
      const legacy = legacyProfileDetails(
        data, draft.get("client_id") === actor.uid ? draft.get("answers") : undefined,
        submitted.get("client_id") === actor.uid ? submitted.get("answers") : undefined,
      );
      const details = Object.fromEntries(clientProfileFields.map(field => [
        field, typeof data[field] === "string" ? data[field] : legacy[field] ?? null,
      ]));
      return {
        ...account, ...details,
        guardian_consent_confirmed: hasValidPrivacyAcceptance(acceptance.data()) &&
          acceptance.get("guardian_consent_confirmed") === true,
      };
    });
  }
  async editOwnProfile(actor: AuthenticatedUser, body: Record<string, unknown>) {
    requirePermission(actor.role, "edit_own_profile");
    if (Object.keys(body).some(key => ["role", "permissions", "account_status", "uid", "id"].includes(key))) {
      throw new PermissionDeniedError("An account cannot assign its own role or status.");
    }
    const allowed = actor.role === "client"
      ? ["full_name", ...clientProfileFields, "guardian_consent_confirmed"] : ["full_name"];
    if (Object.keys(body).some(key => !allowed.includes(key)) || typeof body.full_name !== "string" ||
        body.full_name.trim().length < 1 || body.full_name.trim().length > 120) {
      throw new AccountInputError("Supply a full name of 1 to 120 characters.");
    }
    const update: Record<string, unknown> = { full_name: body.full_name.trim() };
    const email = body.contact_email;
    const phone = body.contact_phone;
    if (email !== undefined) {
      if (email !== null && (typeof email !== "string" || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))) {
        throw new AccountInputError("Enter a valid contact email.");
      }
      update.contact_email = email;
    }
    if (phone !== undefined) {
      if (phone !== null && (typeof phone !== "string" || phone.length > 32 ||
          !/^\+?[0-9 ().-]+$/.test(phone) || !/^\d{7,15}$/.test(phone.replace(/\D/g, "")))) {
        throw new AccountInputError("Enter a phone number with 7 to 15 digits.");
      }
      update.contact_phone = phone;
    }
    let age: number | undefined;
    if (body.date_of_birth !== undefined) {
      try {
        if (typeof body.date_of_birth === "string") age = intakeAge(body.date_of_birth, new Date());
      } catch {
        throw new AccountInputError("Enter a valid date of birth.");
      }
      if (age === undefined) throw new AccountInputError("Enter a valid date of birth.");
      update.date_of_birth = body.date_of_birth;
    }
    if (body.guardian_consent_confirmed !== undefined && typeof body.guardian_consent_confirmed !== "boolean") {
      throw new AccountInputError("Supply a valid guardian confirmation.");
    }
    await this.firestore.runTransaction(async transaction => {
      const reference = this.firestore.collection("users").doc(actor.uid);
      const data = (await transaction.get(reference)).data()!;
      const current = accountFrom(actor.uid, data);
      if (!accountMatchesActor(current, actor)) throw new PermissionDeniedError();
      const audit = new FirestoreAuditWriter(this.firestore);
      const correlationId = randomUUID();
      if (age !== undefined && age < 18) {
        const acceptanceRef = this.firestore.doc(`privacy_acceptances/${actor.uid}`);
        const acceptance = await transaction.get(acceptanceRef);
        if (!hasValidPrivacyAcceptance(acceptance.data())) throw new PermissionDeniedError("Accept the Privacy Policy first.");
        if (acceptance.get("guardian_consent_confirmed") !== true) {
          if (body.guardian_consent_confirmed !== true) {
            throw new AccountInputError("Confirm permission from a parent or guardian before saving.");
          }
          transaction.update(acceptanceRef, {
            guardian_consent_confirmed: true, guardian_consent_confirmed_at: FieldValue.serverTimestamp(),
          });
          audit.appendInTransaction(transaction, {
            actor, action: "privacy.accepted", targetType: "account", targetId: actor.uid,
            clientId: actor.uid, status: "guardian_confirmed", outcome: "succeeded", correlationId,
          });
        }
      }
      if (Object.entries(update).every(([field, value]) => data[field] === value)) return;
      transaction.update(reference, { ...update, updated_at: FieldValue.serverTimestamp() });
      audit.appendInTransaction(transaction, {
        actor, action: "account.updated", targetType: "account", targetId: actor.uid,
        outcome: "succeeded", correlationId,
      });
    });
    return this.ownProfile(actor);
  }
  async change(actor: AuthenticatedUser, uid: string, body: Record<string, unknown>): Promise<Account> {
    identifier(uid);
    if (actor.uid === uid) throw new PermissionDeniedError("Administrators cannot change their own role or status.");
    if (Object.hasOwn(body, "audit_read")) {
      if (Object.keys(body).length !== 1 || typeof body.audit_read !== "boolean") {
        throw new AccountInputError("Supply one boolean audit_read permission.");
      }
      return this.changeAuditRead(actor, uid, body.audit_read);
    }
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
      if (!accountMatchesActor(admin, actor)) throw new PermissionDeniedError("The actor authority has changed.");
      requirePermission(admin.role, isRole ? "manage_user_roles" : accountManagementPermission(target.role));
      const role = isRole ? body.role as UserRole : target.role;
      const status = isRole ? target.account_status : body.account_status as Account["account_status"];
      if (role === target.role && status === target.account_status) return;
      // Assignment versions prevent old team grants returning after a later promotion.
      transaction.update(targetRef, { role, account_status: status, role_revision: target.role_revision + 1,
        ...(target.audit_read && (role !== target.role || status === "inactive")
          ? { "permissions.audit_read": FieldValue.delete() } : {}),
        ...(!isRole ? { deactivated_at: status === "inactive" ? FieldValue.serverTimestamp() : FieldValue.delete(),
          deactivation_reason: status === "inactive" && typeof body.reason === "string" ? body.reason.trim() : FieldValue.delete() } : {}),
        updated_at: FieldValue.serverTimestamp() });
      transaction.set(this.firestore.collection("account_access").doc(uid), {
        revision: target.role_revision + 1, updated_at: FieldValue.serverTimestamp(),
      });
      const operationId = randomUUID();
      const trustedActor: AuthenticatedUser = { uid: admin.id, role: admin.role, displayName: admin.full_name || admin.id, roleRevision: admin.role_revision };
      new FirestoreAuditWriter(this.firestore).appendInTransaction(transaction, {
        actor: trustedActor, action: isRole ? "account.role_changed" : status === "inactive" ? "account.deactivated" : "account.reactivated",
        targetType: "account", targetId: uid, version: target.role_revision + 1, status,
        outcome: "succeeded", operationId, correlationId: operationId,
      });
      transaction.create(this.firestore.collection("account_auth_operations").doc(operationId), {
        target_id: uid, revision: target.role_revision + 1, actor: trustedActor,
        correlation_id: operationId, state: "requested", requested_at: FieldValue.serverTimestamp(), attempt_count: 0,
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
  private async changeAuditRead(actor: AuthenticatedUser, uid: string, enabled: boolean): Promise<Account> {
    await this.firestore.runTransaction(async transaction => {
      const targetRef = this.firestore.collection("users").doc(uid);
      const [admin, staff] = await Promise.all([
        transaction.get(this.firestore.collection("users").doc(actor.uid)),
        transaction.get(targetRef),
      ]);
      const operator = accountFrom(admin.id, admin.data());
      const target = accountFrom(staff.id, staff.data());
      if (!accountMatchesActor(operator, actor) || target.role !== "staff" || target.account_status !== "active") {
        throw new PermissionDeniedError();
      }
      requirePermission(operator.role, "manage_user_roles");
      if ((target.audit_read === true) === enabled) return;
      transaction.update(targetRef, { "permissions.audit_read": enabled, updated_at: FieldValue.serverTimestamp() });
      transaction.set(this.firestore.collection("account_access").doc(uid), {
        revision: target.role_revision, updated_at: FieldValue.serverTimestamp(),
      });
      new FirestoreAuditWriter(this.firestore).appendInTransaction(transaction, {
        actor: { uid: operator.id, role: operator.role, displayName: operator.full_name || operator.id },
        action: "account.updated", targetType: "account", targetId: uid,
        status: enabled ? "audit_read_granted" : "audit_read_revoked",
        outcome: "succeeded", correlationId: randomUUID(),
      });
    });
    return this.get(uid);
  }
  async assertAssigned(actor: AuthenticatedUser, clientId: string, transaction?: Transaction) {
    requirePermission(actor.role, "view_assigned_clients");
    const assignment = await getCurrentAssignment(this.firestore, clientId, transaction);
    if (!assignment || !assignmentIncludesActor(actor, assignment)) {
      throw new PermissionDeniedError("The client is outside the current assignment.");
    }
    const reference = this.firestore.collection("users").doc(actor.uid);
    const current = accountFrom(actor.uid, (transaction ? await transaction.get(reference) : await reference.get()).data());
    if (!accountMatchesActor(current, actor)) throw new PermissionDeniedError();
    return assignment.data;
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
      if (!accountMatchesActor(admin, actor)) throw new PermissionDeniedError();
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
      if (dietitian && await new FirestorePackageService(this.firestore).assignmentStatus(clientId, transaction) !== "active") {
        throw new PackageError(409, inactivePackageAssignmentMessage);
      }
      const sameAssignment = before?.active === true && before.dietitian_id === dietitian &&
        before.client_role_revision === client.role_revision && before.dietitian_role_revision === revisions[dietitian ?? ""] &&
        JSON.stringify(before.team_member_ids ?? before.staff_ids ?? []) === JSON.stringify(staff) &&
        JSON.stringify(before.team_member_role_revisions ?? before.staff_role_revisions ?? {}) ===
          JSON.stringify(Object.fromEntries(staff.map(id => [id, revisions[id]])));
      const previousVersion = Number.isSafeInteger(before?.version) && before!.version > 0 ? before!.version as number : 0;
      transaction.set(ref, { active: dietitian !== null, client_id: clientId, dietitian_id: dietitian, staff_ids: staff,
        team_member_ids: staff,
        client_role_revision: client.role_revision,
        dietitian_role_revision: dietitian ? revisions[dietitian] : null,
        staff_role_revisions: Object.fromEntries(staff.map(id => [id, revisions[id]])),
        team_member_role_revisions: Object.fromEntries(staff.map(id => [id, revisions[id]])),
        assigned_at: sameAssignment && typeof before?.assigned_at === "string" ? before.assigned_at : new Date().toISOString(),
        assigned_by_id: sameAssignment && typeof before?.assigned_by_id === "string" ? before.assigned_by_id : actor.uid,
        version: sameAssignment ? Math.max(1, previousVersion) : previousVersion + 1,
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
  const permissions: Permission[] = [...rolePermissions[account.role]];
  if (account.role === "staff" && account.audit_read) permissions.push("view_audit_logs");
  return { account, permissions };
}
