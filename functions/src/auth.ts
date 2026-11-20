import { UserRecord, getAuth } from "firebase-admin/auth";

import { AuthenticatedUser, normalizeUserRole } from "./domain";

export const { staffSessionMatches }: {
  staffSessionMatches: (user: UserRecord, actor: AuthenticatedUser) => boolean;
} = require("../src/session.cjs");

export interface AuthVerifier {
  verifyIdToken(token: string): Promise<AuthenticatedUser>;
}

export class AuthenticationError extends Error {
  constructor(
    message: string,
    readonly statusCode: 401 | 403 = 401,
  ) {
    super(message);
    this.name = "AuthenticationError";
  }
}

export class FirebaseAuthVerifier implements AuthVerifier {
  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    try {
      const auth = getAuth();
      const decodedToken = await auth.verifyIdToken(token, true);
      const role = normalizeUserRole(decodedToken.role);
      if (role === null) {
        throw new AuthenticationError(
          "This account does not have a valid FitNep role.",
          403,
        );
      }
      const displayName = firstNonEmptyString(
        decodedToken.name,
        decodedToken.email,
      );
      const actor: AuthenticatedUser = {
        uid: decodedToken.uid,
        role,
        ...(decodedToken.email === undefined ? {} : { email: decodedToken.email }),
        ...(typeof decodedToken.staffRoleVersion === "string"
          ? { staffRoleVersion: decodedToken.staffRoleVersion } : {}),
        ...(decodedToken.mustChangePassword === true ? {
          mustChangePassword: true,
          ...(decodedToken.firebase.sign_in_provider === "password"
            ? { passwordAuthenticatedAt: decodedToken.auth_time } : {}),
        } : {}),
        ...(displayName === null ? {} : { displayName }),
      };
      if (role !== "client" && !staffSessionMatches(await auth.getUser(actor.uid), actor)) {
        throw new AuthenticationError("Your staff session changed. Sign in again.");
      }
      return actor;
    } catch (error) {
      if (error instanceof AuthenticationError) throw error;
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
