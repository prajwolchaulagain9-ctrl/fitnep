import { Auth, getAuth } from "firebase-admin/auth";

import { getFirestore } from "firebase-admin/firestore";
import { AuthenticatedUser, UserRole } from "./domain";
import { Account, FirestoreAccountService } from "./account_service";
import { PermissionDeniedError } from "./authorization_policy";
import { hasPermission } from "./authorization_policy";
export const { staffSessionMatches } = require("../src/session.cjs");

export interface AuthVerifier {
  verifyIdToken(token: string): Promise<AuthenticatedUser>;
}

export class AuthenticationError extends Error {
  constructor(
    message: string,
    readonly statusCode: 401 | 403 | 503 = 401,
    readonly identity?: { uid: string; role: UserRole | null },
    readonly code: string = "unauthenticated",
  ) {
    super(message);
    this.name = "AuthenticationError";
  }
}

export class FirebaseAuthVerifier implements AuthVerifier {
  private readonly accounts?: { auth: Pick<Auth, "verifyIdToken" | "getUser">; current(uid: string): Promise<Account> };
  constructor(input?: { auth: Pick<Auth, "verifyIdToken" | "getUser">; current(uid: string): Promise<Account> } | Auth) {
    this.accounts = input && "current" in input ? input : input
      ? new FirestoreAccountService(getFirestore(input.app), input) : undefined;
  }
  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    let uid: string | undefined;
    let currentRole: UserRole | null = null;
    try {
      const decodedToken = await (this.accounts?.auth ?? getAuth()).verifyIdToken(token, true);
      uid = decodedToken.uid;
      const identity = await (this.accounts?.auth ?? getAuth()).getUser(uid);
      const account = await (this.accounts ??
        new FirestoreAccountService(getFirestore(), getAuth())).current(uid);
      currentRole = account.role;
      if (identity.disabled || account.account_status !== "active") {
        throw new AuthenticationError(
          "This account is inactive. Contact FitNEP support.", 403,
          { uid, role: account.role },
        );
      }
      // Credential generation is separate from business role authority.
      // Role changes apply from Firestore without trusting stale token claims.
      if (identity.customClaims?.staffRoleVersion !== undefined &&
          (identity.customClaims.staffRoleVersion !== decodedToken.staffRoleVersion ||
           identity.email !== decodedToken.email)) {
        throw new AuthenticationError("Your credential session changed. Sign in again.");
      }
      const displayName = firstNonEmptyString(
        account.full_name, account.email,
      );
      return {
        uid: decodedToken.uid,
        role: account.role,
        roleRevision: account.role_revision,
        emailVerified: identity.emailVerified === true && decodedToken.email_verified === true,
        email: identity.email,
        authTime: decodedToken.auth_time,
        roleVersion: account.role_revision,
        staffRoleVersion: typeof decodedToken.staffRoleVersion === "string" ? decodedToken.staffRoleVersion : undefined,
        passwordAuthenticatedAt: decodedToken.firebase?.sign_in_provider === "password" ? decodedToken.auth_time : undefined,
        mustChangePassword: identity.customClaims?.mustChangePassword === true || identity.customClaims?.must_change_password === true,
        permissions: { auditRead: hasPermission(account.role, "view_audit_logs"),
          paymentsVerify: hasPermission(account.role, "manage_business_settings") },
        ...(displayName === null ? {} : { displayName }),
      };
    } catch (error) {
      if (error instanceof AuthenticationError) throw error;
      if (error instanceof PermissionDeniedError) {
        throw new AuthenticationError(error.message, 403,
          uid ? { uid, role: currentRole } : undefined);
      }
      if (!(error as { code?: string }).code?.startsWith("auth/")) {
        throw new AuthenticationError("Session verification is unavailable. Try again.", 503);
      }
      throw new AuthenticationError("The authentication token is invalid.");
    }
  }
}

function firstNonEmptyString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}
