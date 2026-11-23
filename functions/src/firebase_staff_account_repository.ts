import { createHash, randomBytes, randomUUID, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { Auth, UserRecord } from "firebase-admin/auth";
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";

import { FirestoreAccountService } from "./account_service";
import { hasPermission } from "./authorization_policy";
import { staffSessionMatches } from "./auth";
import { AuthenticatedUser, StaffAccount, normalizeUserRole } from "./domain";
import {
  InvalidStaffAccountCursorError,
  NewStaffAccount,
  StaffAccountAction,
  StaffAccountChanges,
  StaffAccountError,
  StaffAccountHistoryPage,
  StaffAccountPage,
  StaffAccountRepository,
} from "./staff_account_repository";

const deriveKey = promisify(scrypt);
const lockDurationMs = 120_000;

interface TemporaryPassword {
  salt: string;
  digest: string;
}

interface StaffAccountEvent {
  status: "pending" | "completed";
  before: StaffAccount | null;
  after: StaffAccount;
  requested: StaffAccountChanges;
  roleVersion: string;
  previousRoleVersion?: string | null;
  requiresNewSession: boolean;
}

interface StaffAccountStatusEvent {
  status: "pending" | "completed";
  before: StaffAccount;
  after: StaffAccount;
  roleVersion: string;
}

export class FirebaseStaffAccountRepository implements StaffAccountRepository {
  constructor(
    private readonly auth: Auth,
    private readonly database: Firestore,
    private readonly accountsPerPage = 100,
  ) {}

  private get accounts() { return new FirestoreAccountService(this.database, this.auth); }

  async list(cursor?: string): Promise<StaffAccountPage> {
    const page = await this.auth.listUsers(this.accountsPerPage, cursor).catch(
      (error: unknown) => {
        if (firebaseErrorCode(error) === "auth/invalid-page-token") {
          throw new InvalidStaffAccountCursorError();
        }
        throw error;
      },
    );
    return {
      accounts: (await Promise.all(page.users.map(async user => {
        const account = await this.accounts.current(user.uid);
        return account.role === "client" ? [] : [{ uid: user.uid, name: user.displayName ?? null,
          email: user.email ?? null, role: account.role, isActive: !user.disabled && account.account_status === "active" }];
      }))).flat(),
      nextCursor: page.pageToken ?? null,
    };
  }

  async listHistory(cursor?: string): Promise<StaffAccountHistoryPage> {
    let query = this.database.collection("staff_account_history").orderBy("completed_at", "desc");
    if (cursor) {
      const entry = await this.history(cursor).get();
      if (entry.get("status") !== "completed" || !(entry.get("completed_at") instanceof Timestamp)) {
        throw new InvalidStaffAccountCursorError();
      }
      query = query.startAfter(entry);
    }

    const page = await query.limit(this.accountsPerPage + 1).get();
    const docs = page.docs.slice(0, this.accountsPerPage);
    return {
      entries: docs.map((doc) => ({
        id: doc.id,
        action: doc.get("action") as StaffAccountAction,
        actorUid: doc.get("actor_uid") as string,
        actorName: doc.get("actor_name") as string | null,
        before: doc.get("before") as StaffAccount | null,
        after: doc.get("after") as StaffAccount,
        completedAt: (doc.get("completed_at") as Timestamp).toDate().toISOString(),
      })),
      nextCursor: page.size > docs.length ? docs[docs.length - 1]!.id : null,
    };
  }

  async create(actor: AuthenticatedUser, input: NewStaffAccount): Promise<StaffAccount> {
    const uid = `team-${key(actor.uid, input.requestId)}`;
    const eventRef = this.history(`create-${key(uid)}`);
    const setupRef = this.passwordSetup(uid);
    const requested = { name: input.name, email: input.email, role: input.role };

    return this.withWriteLock(async () => {
      await this.requireCurrentAdmin(actor);
      let event = readEvent((await eventRef.get()).data());
      if (event && !sameFields(event.requested, requested)) {
        throw new StaffAccountError(409, "This request ID was used for different account details.");
      }
      if (event?.status === "completed") {
        return this.getStaffAccount(uid);
      }
      if (!event) {
        event = {
          status: "pending",
          before: null,
          after: { uid, ...requested, isActive: true },
          requested,
          roleVersion: randomUUID(),
          requiresNewSession: false,
        };
        const setup = await passwordVerifier(input.temporaryPassword);
        const batch = this.database.batch();
        batch.create(eventRef, { ...event, ...auditFields(actor, uid, "created") });
        batch.create(setupRef, setup);
        await batch.commit();
      }

      let user = await this.findUser(uid);
      if (!user || user.disabled) {
        const setup = (await setupRef.get()).data() as TemporaryPassword | undefined;
        if (!setup || !await matchesPassword(input.temporaryPassword, setup)) {
          throw new StaffAccountError(409, "Retry this request with the original temporary password.");
        }
        if (!user) {
          try {
            user = await this.auth.createUser({
              uid,
              email: input.email,
              displayName: input.name,
              password: input.temporaryPassword,
              disabled: true,
            });
          } catch (error) {
            if (isRejectedCreation(error)) {
              // Firebase rejected creation before creating the Auth user.
              // Keep the reservation only when the outcome is uncertain.
              await this.database.batch().delete(eventRef).delete(setupRef)
                .commit().catch(() => undefined);
            }
            throw error;
          }
        }
        await this.auth.setCustomUserClaims(uid, {
          ...user.customClaims,
          role: input.role,
          staffRoleVersion: event.roleVersion,
          role_version: 1,
          mustChangePassword: true,
        });
        // Audit and password setup are durable before anyone can sign in.
        await this.auth.updateUser(uid, { disabled: false });
      }
      await this.accounts.provision(await this.auth.getUser(uid));
      await eventRef.update({ status: "completed", completed_at: FieldValue.serverTimestamp() });
      return this.getStaffAccount(uid);
    });
  }

  async changeTemporaryPassword(actor: AuthenticatedUser, newPassword: string): Promise<void> {
    await this.withWriteLock(async () => {
      const { uid } = actor;
      await this.finishPendingStatusChange(uid);
      const user = await this.findUser(uid);
      if (!user || actor.role === "client" || actor.mustChangePassword !== true ||
          !staffSessionMatches(user, actor)) {
        throw new StaffAccountError(403, "Sign in again to change your temporary password.");
      }
      const setupRef = this.passwordSetup(uid);
      const setup = (await setupRef.get()).data() as TemporaryPassword | undefined;
      if (!setup) {
        throw new StaffAccountError(503, "Password setup is unavailable. Contact your administrator.");
      }
      if (await matchesPassword(newPassword, setup)) {
        throw new StaffAccountError(400, "Choose a password different from your temporary password.");
      }

      await this.auth.updateUser(uid, { password: newPassword });
      // A retry can still finish setup if the password write succeeded but
      // revocation or the custom claims update failed.
      await this.auth.revokeRefreshTokens(uid);
      const claims: Record<string, unknown> = {
        ...user.customClaims,
        staffRoleVersion: randomUUID(),
        role_version: nextRoleVersion(user),
      };
      delete claims.mustChangePassword;
      delete claims.must_change_password;
      await this.auth.setCustomUserClaims(uid, claims);
      await setupRef.delete().catch(() => undefined);
    });
  }

  async update(
    actor: AuthenticatedUser, uid: string, changes: StaffAccountChanges, requestId: string,
  ): Promise<StaffAccount> {
    return this.withWriteLock(async () => {
      await this.requireCurrentAdmin(actor);
      await this.finishPendingStatusChange(uid);
      const user = await this.findUser(uid);
      const current = user && await this.getStaffAccount(uid);
      if (!user || !current) throw new StaffAccountError(404, "Staff account not found.");

      const creation = (await this.history(`create-${key(uid)}`).get()).data();
      if (creation?.status === "pending") {
        throw new StaffAccountError(409, "Finish creating this account before editing it.");
      }

      const eventRef = this.history(`edit-${key(actor.uid, uid, requestId)}`);
      const currentRoleVersion = user.customClaims?.staffRoleVersion ?? null;
      let event = readEvent((await eventRef.get()).data());
      if (event && !sameFields(event.requested, changes)) {
        throw new StaffAccountError(409, "This request ID was used for different account changes.");
      }
      if (event?.status === "completed") return current;
      if (!event) {
        const after = { ...current, ...changes };
        if (sameFields(current, after)) return current;
        const roleChanged = after.role !== current.role;
        const emailChanged = after.email !== current.email;
        if (uid === actor.uid && (roleChanged || emailChanged)) {
          throw new StaffAccountError(403, "Another administrator must change your role or email.");
        }
        event = {
          status: "pending",
          before: current,
          after,
          requested: changes,
          roleVersion: randomUUID(),
          previousRoleVersion: currentRoleVersion,
          requiresNewSession: roleChanged || emailChanged,
        };
        await eventRef.create({
          ...event,
          ...auditFields(actor, uid, roleChanged ? "role_changed" : "updated"),
        });
      } else if (!event.before ||
          (currentRoleVersion !== (event.previousRoleVersion ?? null) &&
           currentRoleVersion !== event.roleVersion) ||
          !canResumeEdit(current, event.before, event.after)) {
        throw new StaffAccountError(409, "Account details changed. Review them and start a new request.");
      }

      const { after } = event;
      if (after.name !== current.name || after.email !== current.email) {
        await this.auth.updateUser(uid, {
          ...(after.name !== current.name ? { displayName: after.name } : {}),
          ...(after.email !== current.email && after.email !== null
            ? { email: after.email, emailVerified: false } : {}),
        });
      }
      if (after.role !== (await this.accounts.current(uid)).role) {
        await this.accounts.change(actor, uid, { role: after.role });
      }
      if (event.requiresNewSession && currentRoleVersion !== event.roleVersion) {
        await this.auth.revokeRefreshTokens(uid);
        await this.auth.setCustomUserClaims(uid, {
          ...user.customClaims,
          role: after.role,
          staffRoleVersion: event.roleVersion,
          role_version: nextRoleVersion(user),
        });
      }
      await eventRef.update({ status: "completed", completed_at: FieldValue.serverTimestamp() });
      return this.getStaffAccount(uid);
    });
  }

  async setActive(
    actor: AuthenticatedUser, uid: string, active: boolean, requestId: string,
  ): Promise<StaffAccount> {
    return this.withWriteLock(async () => {
      await this.requireCurrentAdmin(actor);
      if (uid === actor.uid && !active) {
        throw new StaffAccountError(403, "Another administrator must deactivate your account.");
      }

      const eventRef = this.history(`status-${key(actor.uid, uid, requestId)}`);
      const existing = (await eventRef.get()).data() as StaffAccountStatusEvent | undefined;
      if (existing && existing.after.isActive !== active) {
        throw new StaffAccountError(409, "This request ID was used for a different account status.");
      }
      if (existing?.status === "completed") return this.getStaffAccount(uid);

      await this.finishPendingStatusChange(uid);
      const current = await this.getStaffAccount(uid);
      if (existing) return current;

      if (current.isActive === active) {
        // Reserve the request ID even when no status change was needed.
        // Without a completion timestamp this receipt stays out of the audit feed.
        await eventRef.create({ status: "completed", before: current, after: current });
        return current;
      }

      const creation = await this.history(`create-${key(uid)}`).get();
      if (creation.get("status") === "pending") {
        throw new StaffAccountError(409, "Finish creating this account before changing its status.");
      }
      const event: StaffAccountStatusEvent = {
        status: "pending",
        before: current,
        after: { ...current, isActive: active },
        roleVersion: randomUUID(),
      };
      // Keep the audit entry and its retry pointer together before changing Auth.
      await this.database.batch()
        .create(eventRef, { ...event, ...auditFields(actor, uid, active ? "reactivated" : "deactivated") })
        .create(this.statusChange(uid), { event_id: eventRef.id })
        .commit();
      await this.applyStatusChange(uid, eventRef, event);
      return event.after;
    });
  }

  private statusChange(uid: string) {
    return this.database.collection("staff_account_locks").doc(`status-${key(uid)}`);
  }

  private async finishPendingStatusChange(uid: string): Promise<void> {
    const eventId = (await this.statusChange(uid).get()).get("event_id") as string | undefined;
    if (!eventId) return;
    const eventRef = this.history(eventId);
    const event = (await eventRef.get()).data() as StaffAccountStatusEvent;
    await this.applyStatusChange(uid, eventRef, event);
  }

  private async applyStatusChange(
    uid: string, eventRef: FirebaseFirestore.DocumentReference, event: StaffAccountStatusEvent,
  ): Promise<void> {
    const user = await this.findUser(uid);
    if (!user || (await this.accounts.current(uid)).role === "client") throw new StaffAccountError(404, "Staff account not found.");
    const active = event.after.isActive;
    if (!active && !user.disabled) await this.auth.updateUser(uid, { disabled: true });
    const actorUid = (await eventRef.get()).get("actor_uid") as string;
    const actorAccount = await this.accounts.current(actorUid);
    await this.accounts.change({ uid: actorUid, role: actorAccount.role }, uid, { account_status: active ? "active" : "inactive" });
    if (user.customClaims?.staffRoleVersion !== event.roleVersion) {
      await this.auth.revokeRefreshTokens(uid);
      await this.auth.setCustomUserClaims(uid, {
        ...user.customClaims,
        staffRoleVersion: event.roleVersion,
        role_version: nextRoleVersion(user),
      });
    }
    // Only re-enable sign-in once the previous sessions have been invalidated.
    if (active && user.disabled) await this.auth.updateUser(uid, { disabled: false });
    await this.database.batch()
      .update(eventRef, { status: "completed", completed_at: FieldValue.serverTimestamp() })
      .delete(this.statusChange(uid))
      .commit();
  }

  private async requireCurrentAdmin(actor: AuthenticatedUser) {
    const user = await this.findUser(actor.uid);
    const account = user && await this.accounts.current(actor.uid);
    if (!user || !account || account.account_status !== "active" || !hasPermission(account.role, "manage_staff_accounts") || actor.mustChangePassword ||
        (user.customClaims?.staffRoleVersion !== undefined && user.customClaims.staffRoleVersion !== actor.staffRoleVersion)) {
      throw new StaffAccountError(403, "Administrator access is required.");
    }
  }

  private async getStaffAccount(uid: string): Promise<StaffAccount> {
    const user = await this.findUser(uid);
    const account = user && await this.accounts.current(uid);
    if (!user || !account || account.role === "client") throw new StaffAccountError(404, "Staff account not found.");
    return { uid, name: user.displayName ?? null, email: user.email ?? null, role: account.role,
      isActive: !user.disabled && account.account_status === "active" };
  }

  private async findUser(uid: string): Promise<UserRecord | null> {
    try {
      return await this.auth.getUser(uid);
    } catch (error) {
      if (firebaseErrorCode(error) === "auth/user-not-found") return null;
      throw error;
    }
  }

  private history(id: string) {
    return this.database.collection("staff_account_history").doc(id);
  }

  private passwordSetup(uid: string) {
    return this.database.collection("staff_password_setup").doc(uid);
  }

  // Serialize Auth changes so a retry cannot apply stale claims or overwrite
  // another administrator's change after reading the old account.
  private async withWriteLock<T>(operation: () => Promise<T>): Promise<T> {
    const lock = this.database.collection("staff_account_locks").doc("writes");
    const owner = randomUUID();
    await this.database.runTransaction(async (transaction) => {
      const current = await transaction.get(lock);
      if ((current.get("expires_at_ms") ?? 0) > Date.now()) {
        throw new StaffAccountError(409, "Staff accounts are being updated. Please retry.");
      }
      transaction.set(lock, { owner, expires_at_ms: Date.now() + lockDurationMs });
    });
    try {
      return await operation();
    } catch (error) {
      const code = firebaseErrorCode(error);
      if (code === "auth/email-already-exists") {
        throw new StaffAccountError(409, "An account already uses that email address.");
      }
      if (code === "auth/invalid-password" || code === "auth/password-does-not-meet-requirements") {
        throw new StaffAccountError(400, "The password does not meet Firebase's requirements.");
      }
      if (code === "auth/invalid-email") {
        throw new StaffAccountError(400, "Enter a valid email address.");
      }
      if (error instanceof StaffAccountError) throw error;
      // Firebase errors can contain credential data in request details.
      throw new StaffAccountError(503, "Staff account changes are temporarily unavailable. Please retry.");
    } finally {
      await this.database.runTransaction(async (transaction) => {
        if ((await transaction.get(lock)).get("owner") === owner) transaction.delete(lock);
      }).catch(() => undefined);
    }
  }
}

function nextRoleVersion(user: UserRecord): number {
  const version = user.customClaims?.role_version ?? 0;
  if (!Number.isSafeInteger(version) || version < 0 || version >= Number.MAX_SAFE_INTEGER) {
    throw new StaffAccountError(409, "This account needs a valid role version.");
  }
  return version + 1;
}

function staffAccount(user: UserRecord): StaffAccount | null {
  const role = normalizeUserRole(user.customClaims?.role);
  if (role === null || role === "client") return null;
  return {
    uid: user.uid,
    name: user.displayName ?? null,
    email: user.email ?? null,
    role,
    isActive: !user.disabled,
  };
}

function key(...parts: string[]): string {
  return createHash("sha256").update(JSON.stringify(parts)).digest("hex").slice(0, 40);
}

function readEvent(data: FirebaseFirestore.DocumentData | undefined): StaffAccountEvent | null {
  return data ? data as StaffAccountEvent : null;
}

function sameFields(left: object, right: object): boolean {
  const expected = new Map(Object.entries(right));
  const actual = Object.entries(left);
  return actual.length === expected.size &&
    actual.every(([field, value]) => expected.has(field) && expected.get(field) === value);
}

function canResumeEdit(current: StaffAccount, before: StaffAccount, after: StaffAccount): boolean {
  return (["name", "email", "role", "isActive"] as const).every((field) =>
    current[field] === before[field] || current[field] === after[field],
  );
}

function auditFields(actor: AuthenticatedUser, uid: string, action: StaffAccountAction) {
  return {
    action,
    actor_uid: actor.uid,
    actor_name: actor.displayName ?? null,
    target_uid: uid,
    created_at: FieldValue.serverTimestamp(),
  };
}

function firebaseErrorCode(error: unknown): string | undefined {
  return error instanceof Error && "code" in error && typeof error.code === "string"
    ? error.code : undefined;
}

function isRejectedCreation(error: unknown): boolean {
  const code = firebaseErrorCode(error);
  return code === "auth/email-already-exists" ||
    code === "auth/invalid-email" ||
    code === "auth/invalid-password" ||
    code === "auth/password-does-not-meet-requirements";
}

async function passwordVerifier(password: string): Promise<TemporaryPassword> {
  const salt = randomBytes(16).toString("hex");
  const digest = (await deriveKey(password, salt, 32) as Buffer).toString("hex");
  return { salt, digest };
}

async function matchesPassword(password: string, setup: TemporaryPassword): Promise<boolean> {
  const digest = await deriveKey(password, setup.salt, 32) as Buffer;
  const expected = Buffer.from(setup.digest, "hex");
  return digest.length === expected.length && timingSafeEqual(digest, expected);
}
