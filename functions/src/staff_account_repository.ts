import { StaffAccount } from "./domain";

export interface StaffAccountPage {
  accounts: StaffAccount[];
  nextCursor: string | null;
}

export interface StaffAccountRepository {
  list(cursor?: string): Promise<StaffAccountPage>;
}

export class InvalidStaffAccountCursorError extends Error {
  constructor() {
    super("Invalid staff directory cursor.");
    this.name = "InvalidStaffAccountCursorError";
  }
}
