import { createHash, randomBytes } from "node:crypto";
import { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";

import { AuditWriter } from "./audit";
import { AuthenticationError } from "./auth";
import { AuthenticatedUser } from "./domain";
import { privacyPolicyVersion } from "./privacy_policy_acceptance";

export const platformSessionHeader = "X-FitNEP-Session";
export const defaultIdleTimeoutSeconds = 15 * 60;

export interface PlatformSessionView {
  uid: string;
  role: AuthenticatedUser["role"];
  role_version: number;
  expires_at: string;
  ready: true;
  permissions: { audit_read: boolean; payments_verify: boolean };
}

export interface PlatformSessionService {
  start(actor: AuthenticatedUser, correlationId: string): Promise<PlatformSessionView & { session_id: string }>;
  verify(actor: AuthenticatedUser, sessionId: string | undefined): Promise<PlatformSessionView>;
  activity(actor: AuthenticatedUser, sessionId: string | undefined): Promise<PlatformSessionView>;
  end(actor: AuthenticatedUser, sessionId: string | undefined, correlationId: string): Promise<void>;
}

export class FirestorePlatformSessionService implements PlatformSessionService {
  constructor(
    private readonly firestore: Firestore,
    private readonly audit: AuditWriter,
    private readonly idleTimeoutSeconds = defaultIdleTimeoutSeconds,
    private readonly now = () => new Date(),
  ) {
    if (!Number.isSafeInteger(idleTimeoutSeconds) || idleTimeoutSeconds < 1 || idleTimeoutSeconds > 86_400) {
      throw new Error("The session idle timeout must be between 1 and 86400 seconds.");
    }
  }

  start(actor: AuthenticatedUser, correlationId: string) {
    assertReady(actor);
    const context = this.context(actor);
    const reference = this.firestore.collection("platform_sessions").doc(randomBytes(32).toString("base64url"));
    return this.firestore.runTransaction(async transaction => {
      await this.assertCurrentReadiness(transaction, actor);
      const previous = (await transaction.get(context)).data();
      if (previous?.closed === true) throw endedSession();
      if (previous?.session_id !== undefined) {
        const session = await this.read(transaction, actor, previous.session_id);
        return { ...this.view(actor, session.expires_at), session_id: previous.session_id as string };
      }
      const createdAt = Timestamp.fromDate(this.now());
      const expiresAt = Timestamp.fromMillis(createdAt.toMillis() + this.idleTimeoutSeconds * 1000);
      transaction.create(reference, {
        uid: actor.uid, role: actor.role, role_version: actor.roleVersion ?? 0,
        auth_time: actor.authTime, created_at: createdAt, last_activity_at: createdAt,
        expires_at: expiresAt, revoked_at: null,
        audit_read: actor.permissions?.auditRead === true,
        payments_verify: actor.permissions?.paymentsVerify === true,
      });
      transaction.create(context, { session_id: reference.id, closed: false });
      this.audit.appendInTransaction(transaction, {
        actor, action: "session.started", targetType: "account", targetId: actor.uid,
        outcome: "succeeded", correlationId,
      });
      return { ...this.view(actor, expiresAt), session_id: reference.id };
    });
  }

  verify(actor: AuthenticatedUser, sessionId: string | undefined) {
    return this.firestore.runTransaction(async transaction => {
      const session = await this.read(transaction, actor, sessionId);
      return this.view(actor, session.expires_at);
    });
  }

  activity(actor: AuthenticatedUser, sessionId: string | undefined) {
    return this.firestore.runTransaction(async transaction => {
      const session = await this.read(transaction, actor, sessionId);
      const now = this.now().getTime();
      // Regular requests never renew expiry; the human-activity endpoint is throttled.
      if (now - session.last_activity_at.toMillis() < 60_000) {
        return this.view(actor, session.expires_at);
      }
      const expiresAt = Timestamp.fromMillis(now + this.idleTimeoutSeconds * 1000);
      transaction.update(this.session(sessionId), {
        last_activity_at: Timestamp.fromMillis(now), expires_at: expiresAt,
      });
      return this.view(actor, expiresAt);
    });
  }

  end(actor: AuthenticatedUser, sessionId: string | undefined, correlationId: string) {
    return this.firestore.runTransaction(async transaction => {
      const reference = this.session(sessionId);
      const data = (await transaction.get(reference)).data();
      if (data?.uid !== actor.uid || data.auth_time !== actor.authTime) throw endedSession();
      const context = this.context(actor);
      await transaction.get(context);
      if (data.revoked_at !== null) return;
      transaction.update(reference, { revoked_at: Timestamp.fromDate(this.now()) });
      transaction.set(context, { session_id: reference.id, closed: true });
      this.audit.appendInTransaction(transaction, {
        actor, action: "session.ended", targetType: "account", targetId: actor.uid,
        outcome: "succeeded", correlationId,
      });
    });
  }

  private async read(transaction: Transaction, actor: AuthenticatedUser, sessionId: string | undefined) {
    await this.assertCurrentReadiness(transaction, actor);
    const data = (await transaction.get(this.session(sessionId))).data();
    if (data?.uid !== actor.uid || data.role !== actor.role ||
      data.role_version !== (actor.roleVersion ?? 0) || data.auth_time !== actor.authTime ||
      data.audit_read !== (actor.permissions?.auditRead === true) ||
      data.payments_verify !== (actor.permissions?.paymentsVerify === true) ||
      data.revoked_at !== null || !(data.expires_at instanceof Timestamp) ||
      !(data.last_activity_at instanceof Timestamp) || data.expires_at.toMillis() <= this.now().getTime()) {
      throw endedSession();
    }
    return { expires_at: data.expires_at, last_activity_at: data.last_activity_at };
  }

  private async assertCurrentReadiness(transaction: Transaction, actor: AuthenticatedUser) {
    assertReady(actor);
    const lock = (await transaction.get(this.firestore.collection("platform_login_state").doc(actor.uid))).data();
    if (lock?.locked_until !== undefined && lock.locked_until !== null) {
      if (!(lock.locked_until instanceof Timestamp)) {
        throw new AuthenticationError("The account login state needs attention.", 503);
      }
      if (lock.locked_until.toMillis() > this.now().getTime()) {
        throw new AuthenticationError("This account is temporarily locked. Try again later.", 403);
      }
    }
    if (actor.role !== "client") return;
    const acceptance = (await transaction.get(this.firestore.collection("privacy_acceptances").doc(actor.uid))).data();
    if (acceptance?.policy_version !== privacyPolicyVersion ||
      !(acceptance.accepted_at instanceof Timestamp) ||
      typeof acceptance.guardian_consent_confirmed !== "boolean" ||
      (acceptance.guardian_consent_confirmed && !(acceptance.guardian_consent_confirmed_at instanceof Timestamp))) {
      throw new AuthenticationError("Complete the current privacy onboarding before continuing.", 403);
    }
  }

  private session(id: string | undefined) {
    if (typeof id !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(id)) throw endedSession();
    return this.firestore.collection("platform_sessions").doc(id);
  }

  private context(actor: AuthenticatedUser) {
    if (!Number.isSafeInteger(actor.authTime) || (actor.authTime ?? 0) < 1) throw endedSession();
    // ponytail: auth_time has second precision; the credential exchange can supply a unique login ID.
    const id = createHash("sha256").update(actor.uid + ":" + actor.authTime).digest("hex");
    return this.firestore.collection("platform_auth_contexts").doc(id);
  }

  private view(actor: AuthenticatedUser, expiresAt: Timestamp): PlatformSessionView {
    return {
      uid: actor.uid, role: actor.role, role_version: actor.roleVersion ?? 0,
      expires_at: expiresAt.toDate().toISOString(), ready: true,
      permissions: {
        audit_read: actor.permissions?.auditRead === true,
        payments_verify: actor.permissions?.paymentsVerify === true,
      },
    };
  }
}

function assertReady(actor: AuthenticatedUser) {
  if (actor.mustChangePassword === true || (actor.role === "client" && actor.emailVerified !== true)) {
    throw new AuthenticationError("Complete account verification and the required password change first.", 403);
  }
  if (!Number.isSafeInteger(actor.authTime) || (actor.authTime ?? 0) < 1) throw endedSession();
}

function endedSession() {
  return new AuthenticationError("Your session ended. Sign in again.");
}
