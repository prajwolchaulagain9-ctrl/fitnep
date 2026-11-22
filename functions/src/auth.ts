import { Auth, getAuth } from "firebase-admin/auth";

import { AuthenticatedUser, normalizeUserRole } from "./domain";

export interface AuthVerifier {
  verifyIdToken(token: string): Promise<AuthenticatedUser>;
}

export class AuthenticationError extends Error {
  constructor(
    message: string,
    readonly statusCode: 401 | 403 | 503 = 401,
  ) {
    super(message);
    this.name = "AuthenticationError";
  }
}

export class FirebaseAuthVerifier implements AuthVerifier {
  constructor(private readonly auth: Pick<Auth, "verifyIdToken" | "getUser"> = getAuth()) {}

  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    try {
      const decodedToken = await this.auth.verifyIdToken(token, true);
      // Cached token claims cannot preserve privileges after an account change.
      const account = await this.auth.getUser(decodedToken.uid);
      if (account.disabled) {
        throw new AuthenticationError("This account is inactive.", 403);
      }
      const claims = account.customClaims ?? {};
      const role = claims.role === undefined && account.emailVerified === true
        ? "client"
        : normalizeUserRole(claims.role);
      if (role === null) {
        throw new AuthenticationError(
          "This account does not have a valid FitNep role.",
          403,
        );
      }
      const displayName = firstNonEmptyString(
        account.displayName,
        account.email,
      );
      const roleVersion = claims.role_version ?? 0;
      if (!Number.isSafeInteger(roleVersion) || roleVersion < 0) {
        throw new AuthenticationError("This account needs a valid role version.", 403);
      }
      return {
        uid: decodedToken.uid,
        role,
        ...(displayName === null ? {} : { displayName }),
        roleVersion,
        authTime: decodedToken.auth_time,
        emailVerified: account.emailVerified,
        mustChangePassword: claims.must_change_password === true,
        permissions: {
          auditRead: role === "admin" || (role === "staff" && claims.permissions?.audit_read === true),
          paymentsVerify: role === "admin" || (role === "staff" && claims.permissions?.payments_verify === true),
        },
      };
    } catch (error) {
      if (error instanceof AuthenticationError) throw error;
      const code = (error as { code?: string } | null)?.code;
      if (["auth/id-token-expired", "auth/id-token-revoked", "auth/invalid-id-token",
        "auth/argument-error", "auth/user-disabled", "auth/user-not-found"].includes(code ?? "")) {
        throw new AuthenticationError("The authentication token is invalid.");
      }
      throw new AuthenticationError("Authentication is temporarily unavailable.", 503);
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
