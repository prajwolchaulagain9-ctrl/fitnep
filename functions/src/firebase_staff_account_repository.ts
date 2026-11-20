import { Auth } from "firebase-admin/auth";

import { StaffAccount, normalizeUserRole } from "./domain";
import {
  InvalidStaffAccountCursorError,
  StaffAccountPage,
  StaffAccountRepository,
} from "./staff_account_repository";

const accountsPerPage = 100;

export class FirebaseStaffAccountRepository implements StaffAccountRepository {
  constructor(private readonly auth: Pick<Auth, "listUsers">) {}

  async list(cursor?: string): Promise<StaffAccountPage> {
    const page = await this.auth.listUsers(accountsPerPage, cursor).catch(
      (error: unknown) => {
        if (
          error instanceof Error &&
          "code" in error &&
          error.code === "auth/invalid-page-token"
        ) {
          throw new InvalidStaffAccountCursorError();
        }
        throw error;
      },
    );

    const accounts: StaffAccount[] = [];
    for (const user of page.users) {
      const role = normalizeUserRole(user.customClaims?.role);
      if (role === null || role === "client") continue;

      accounts.push({
        uid: user.uid,
        name: user.displayName ?? null,
        email: user.email ?? null,
        role,
        isActive: !user.disabled,
      });
    }

    return { accounts, nextCursor: page.pageToken ?? null };
  }
}
