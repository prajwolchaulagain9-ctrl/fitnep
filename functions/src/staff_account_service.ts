import { AuthenticationError } from "./auth";
import { roleCanPerformAction } from "./authorization_policy";
import { AuthenticatedUser, StaffAccountRole, normalizeUserRole } from "./domain";
import {
  InvalidStaffAccountCursorError,
  StaffAccountChanges,
  StaffAccountError,
  StaffAccountRepository,
} from "./staff_account_repository";

export class StaffAccountService {
  constructor(private readonly repository?: StaffAccountRepository) {}

  async list(actor: AuthenticatedUser, cursor: unknown) {
    this.requireAdmin(actor, "listStaffAccounts");
    if (
      cursor !== undefined &&
      (typeof cursor !== "string" || cursor.trim() === "" || cursor.length > 4096)
    ) {
      throw new InvalidStaffAccountCursorError();
    }
    return this.storage().list(cursor);
  }

  async create(actor: AuthenticatedUser, input: Record<string, unknown>) {
    this.requireAdmin(actor, "createStaffAccount");
    return this.storage().create(actor, {
      name: nameFrom(input.name),
      email: emailFrom(input.email),
      role: roleFrom(input.role),
      temporaryPassword: passwordFrom(input.temporary_password),
      requestId: identifier(input.request_id, "Request ID"),
    });
  }

  async changeTemporaryPassword(actor: AuthenticatedUser, input: Record<string, unknown>) {
    const now = Math.floor(Date.now() / 1000);
    if (actor.mustChangePassword !== true ||
        actor.passwordAuthenticatedAt === undefined ||
        actor.passwordAuthenticatedAt < now - 300 ||
        actor.passwordAuthenticatedAt > now + 30) {
      throw new StaffAccountError(403, "Sign in with your current password again to finish setup.");
    }
    await this.storage().changeTemporaryPassword(actor, passwordFrom(input.new_password));
  }

  async update(actor: AuthenticatedUser, uid: string, input: Record<string, unknown>) {
    this.requireAdmin(actor, "updateStaffAccount");
    if (!uid || uid.length > 128) throw new StaffAccountError(400, "Account ID is invalid.");
    const changes: StaffAccountChanges = {};
    if ("name" in input) changes.name = nameFrom(input.name);
    if ("email" in input) changes.email = emailFrom(input.email);
    if ("role" in input) changes.role = roleFrom(input.role);
    if (Object.keys(changes).length === 0) {
      throw new StaffAccountError(400, "Supply a name, email or staff role to update.");
    }
    return this.storage().update(actor, uid, changes, identifier(input.request_id, "Request ID"));
  }

  private requireAdmin(
    actor: AuthenticatedUser,
    action: "listStaffAccounts" | "createStaffAccount" | "updateStaffAccount",
  ): void {
    if (!roleCanPerformAction(actor.role, action) || actor.mustChangePassword) {
      throw new AuthenticationError("Administrator access is required.", 403);
    }
  }

  private storage(): StaffAccountRepository {
    if (!this.repository) throw new StaffAccountError(503, "Staff accounts are not configured.");
    return this.repository;
  }
}

function identifier(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new StaffAccountError(400, `${label} is invalid.`);
  }
  return value;
}

function nameFrom(value: unknown): string {
  if (typeof value !== "string" || !value.trim() || value.trim().length > 100) {
    throw new StaffAccountError(400, "Enter a name of up to 100 characters.");
  }
  return value.trim();
}

function emailFrom(value: unknown): string {
  if (typeof value !== "string" || value.trim().length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())) {
    throw new StaffAccountError(400, "Enter a valid email address.");
  }
  return value.trim().toLowerCase();
}

function roleFrom(value: unknown): StaffAccountRole {
  const role = normalizeUserRole(value);
  if (role === null || role === "client") {
    throw new StaffAccountError(400, "Choose a staff, dietitian or admin role.");
  }
  return role;
}

function passwordFrom(value: unknown): string {
  if (typeof value !== "string" || value.trim().length < 8 || Buffer.byteLength(value) > 128) {
    throw new StaffAccountError(400, "Use at least 8 characters and at most 128 bytes for the password.");
  }
  return value;
}
