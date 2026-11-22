import { getAuth } from "firebase-admin/auth";

import { getFirestore } from "firebase-admin/firestore";
import { AuthenticatedUser, UserRole } from "./domain";
import { FirestoreAccountService } from "./account_service";
import { PermissionDeniedError } from "./authorization_policy";

export interface AuthVerifier {
  verifyIdToken(token: string): Promise<AuthenticatedUser>;
}

export class AuthenticationError extends Error {
  constructor(
    message: string,
    readonly statusCode: 401 | 403 | 503 = 401,
    readonly identity?: { uid: string; role: UserRole | null },
  ) {
    super(message);
    this.name = "AuthenticationError";
  }
}

export class FirebaseAuthVerifier implements AuthVerifier {
  constructor(private readonly accounts?: FirestoreAccountService) {}
  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    let uid: string | undefined;
    let currentRole: UserRole | null = null;
    try {
      const decodedToken = await (this.accounts?.auth ?? getAuth()).verifyIdToken(token, true);
      uid = decodedToken.uid;
      const account = await (this.accounts ??
        new FirestoreAccountService(getFirestore(), getAuth())).current(uid);
      currentRole = account.role;
      if (account.account_status !== "active") {
        throw new AuthenticationError(
          "This account is inactive. Contact FitNEP support.", 403,
          { uid, role: account.role },
        );
      }
      const displayName = firstNonEmptyString(
        account.full_name, account.email,
      );
      return {
        uid: decodedToken.uid,
        role: account.role,
        roleRevision: account.role_revision,
        emailVerified: decodedToken.email_verified === true,
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
