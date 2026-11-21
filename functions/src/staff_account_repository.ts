import { AuthenticatedUser, StaffAccount, StaffAccountRole } from "./domain";

export interface StaffAccountPage {
  accounts: StaffAccount[];
  nextCursor: string | null;
}

export type StaffAccountAction = "created" | "updated" | "role_changed" | "deactivated" | "reactivated";

export interface StaffAccountHistoryEntry {
  id: string;
  action: StaffAccountAction;
  actorUid: string;
  actorName: string | null;
  before: StaffAccount | null;
  after: StaffAccount;
  completedAt: string;
}

export interface StaffAccountHistoryPage {
  entries: StaffAccountHistoryEntry[];
  nextCursor: string | null;
}

export interface NewStaffAccount {
  name: string;
  email: string;
  role: StaffAccountRole;
  temporaryPassword: string;
  requestId: string;
}

export type StaffAccountChanges = Partial<Pick<NewStaffAccount, "name" | "email" | "role">>;

export interface StaffAccountRepository {
  list(cursor?: string): Promise<StaffAccountPage>;
  listHistory(cursor?: string): Promise<StaffAccountHistoryPage>;
  create(actor: AuthenticatedUser, input: NewStaffAccount): Promise<StaffAccount>;
  changeTemporaryPassword(actor: AuthenticatedUser, newPassword: string): Promise<void>;
  update(actor: AuthenticatedUser, uid: string, changes: StaffAccountChanges, requestId: string): Promise<StaffAccount>;
  setActive(actor: AuthenticatedUser, uid: string, active: boolean, requestId: string): Promise<StaffAccount>;
}

export class StaffAccountError extends Error {
  constructor(readonly status: 400 | 403 | 404 | 409 | 503, message: string) {
    super(message);
  }
}

export class InvalidStaffAccountCursorError extends StaffAccountError {
  constructor() {
    super(400, "Invalid staff account page cursor.");
  }
}
