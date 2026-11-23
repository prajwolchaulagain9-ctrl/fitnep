import { AuthenticatedUser } from "./domain";
import { FirestorePackageService } from "./package_membership_service";
import { StaffAccountRepository } from "./staff_account_repository";

export const inactivePackageAssignmentMessage =
  "Only clients with an active package can be assigned.";

export type AssignmentPackageStatus =
  | "active"
  | "pending"
  | "scheduled"
  | "expired"
  | "inactive"
  | "none";

export interface ClientAssignmentRecord {
  clientId: string;
  dietitianId: string;
  active: true;
  assignedAt: string;
  assignedById: string;
}

export interface ClientAssignmentRepository {
  assign(record: ClientAssignmentRecord): Promise<ClientAssignmentRecord>;
}

export interface ClientPackageStatusReader {
  getStatus(clientId: string): Promise<AssignmentPackageStatus>;
}

export interface DietitianDirectory {
  isActiveDietitian(uid: string): Promise<boolean>;
}

export class ClientAssignmentError extends Error {
  constructor(
    readonly statusCode: 400 | 403 | 409 | 503,
    message: string,
  ) {
    super(message);
    this.name = "ClientAssignmentError";
  }
}

export class ClientAssignmentService {
  constructor(
    private readonly repository: ClientAssignmentRepository,
    private readonly packages: ClientPackageStatusReader,
    private readonly dietitians: DietitianDirectory,
    private readonly now = () => new Date(),
  ) {}

  async eligibility(actor: AuthenticatedUser, clientIdInput: unknown) {
    this.requireAdmin(actor);
    const clientId = requiredIdentifier(clientIdInput, "Client id");
    const packageStatus = await this.packages.getStatus(clientId);
    const canAssign = packageStatus === "active";
    return {
      clientId,
      packageStatus,
      canAssign,
      message: canAssign ? null : inactivePackageAssignmentMessage,
    };
  }

  async assign(
    actor: AuthenticatedUser,
    clientIdInput: unknown,
    dietitianIdInput: unknown,
  ): Promise<ClientAssignmentRecord> {
    const eligibility = await this.eligibility(actor, clientIdInput);
    if (!eligibility.canAssign) {
      throw new ClientAssignmentError(409, inactivePackageAssignmentMessage);
    }
    const dietitianId = requiredIdentifier(dietitianIdInput, "Dietitian id");
    if (!(await this.dietitians.isActiveDietitian(dietitianId))) {
      throw new ClientAssignmentError(409, "Select an active dietitian.");
    }
    return this.repository.assign({
      clientId: eligibility.clientId,
      dietitianId,
      active: true,
      assignedAt: this.now().toISOString(),
      assignedById: actor.uid,
    });
  }

  private requireAdmin(actor: AuthenticatedUser): void {
    if (actor.role !== "admin") {
      throw new ClientAssignmentError(
        403,
        "Administrator access is required to assign clients.",
      );
    }
  }
}

/** Reuses the same effective membership statuses returned by the package APIs. */
export class ExistingClientPackageStatusReader
implements ClientPackageStatusReader {
  constructor(private readonly memberships: FirestorePackageService) {}

  async getStatus(clientId: string): Promise<AssignmentPackageStatus> {
    return this.memberships.assignmentStatus(clientId);
  }
}

export class ExistingStaffDietitianDirectory implements DietitianDirectory {
  constructor(private readonly staff: StaffAccountRepository) {}

  async isActiveDietitian(uid: string): Promise<boolean> {
    let cursor: string | undefined;
    const seen = new Set<string>();
    do {
      const page = await this.staff.list(cursor);
      if (page.accounts.some(account =>
        account.uid === uid && account.role === "dietitian" && account.isActive
      )) return true;
      if (page.nextCursor === null) return false;
      if (seen.has(page.nextCursor)) return false;
      seen.add(page.nextCursor);
      cursor = page.nextCursor;
    } while (true);
  }
}

function requiredIdentifier(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new ClientAssignmentError(400, `${label} is invalid.`);
  }
  return value;
}
