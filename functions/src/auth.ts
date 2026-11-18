import { getAuth } from "firebase-admin/auth";

import { AuthenticatedUser, isUserRole, UserRole } from "./domain";

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
      const decodedToken = await getAuth().verifyIdToken(token, true);
      const role = normalizeRole(decodedToken.role);
      if (role === null) {
        throw new AuthenticationError(
          "This account does not have a valid FitNep role.",
          403,
        );
      }
      return { uid: decodedToken.uid, role };
    } catch (error) {
      if (error instanceof AuthenticationError) throw error;
      throw new AuthenticationError("The authentication token is invalid.");
    }
  }
}

function normalizeRole(value: unknown): UserRole | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  return isUserRole(normalized) ? normalized : null;
}
