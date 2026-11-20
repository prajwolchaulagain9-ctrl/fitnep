import { AuthenticationError } from "./auth";
import { roleCanPerformAction } from "./authorization_policy";
import { AuthenticatedUser } from "./domain";
import {
  InvalidStaffAccountCursorError,
  StaffAccountPage,
  StaffAccountRepository,
} from "./staff_account_repository";

export class StaffDirectoryUnavailableError extends Error {
  constructor() {
    super("The staff directory is not configured.");
    this.name = "StaffDirectoryUnavailableError";
  }
}

export class StaffAccountService {
  constructor(private readonly repository?: StaffAccountRepository) {}

  async list(actor: AuthenticatedUser, cursor: unknown): Promise<StaffAccountPage> {
    if (!roleCanPerformAction(actor.role, "listStaffAccounts")) {
      throw new AuthenticationError("Administrator access is required.", 403);
    }
    if (
      cursor !== undefined &&
      (typeof cursor !== "string" || cursor.trim() === "" || cursor.length > 4096)
    ) {
      throw new InvalidStaffAccountCursorError();
    }
    if (!this.repository) throw new StaffDirectoryUnavailableError();

    return this.repository.list(cursor);
  }
}
