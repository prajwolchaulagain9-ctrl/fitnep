import { Auth } from "firebase-admin/auth";
import { AuthenticatedUser } from "./domain";
import { FirestorePackageService } from "./package_membership_service";
import { NotificationWorkflowService } from "./notification_service";
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
  version: number;
}

export interface ClientAssignmentRepository {
  assign(record: ClientAssignmentRecord): Promise<ClientAssignmentRecord>;
  currentClientCounts(): Promise<Record<string, number>>;
  getCurrent(clientId: string): Promise<ClientAssignmentRecord | null>;
}

export interface AssignedClientProfile {
  id: string;
  name: string;
  email: string | null;
}

export interface AssignedClientDirectory {
  getClient(clientId: string): Promise<AssignedClientProfile>;
}

export interface ClientPackageStatusReader {
  getStatus(clientId: string): Promise<AssignmentPackageStatus>;
}

export interface DietitianDirectory {
  isActiveDietitian(uid: string): Promise<boolean>;
}

export class ClientAssignmentError extends Error {
  constructor(
    readonly statusCode: 400 | 403 | 404 | 409 | 503,
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
    private readonly notifications: Pick<NotificationWorkflowService, "clientAssigned"> | null,
    private readonly clients: AssignedClientDirectory | null,
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
    const clientProfile = this.clients !== null
      ? await this.clients.getClient(eligibility.clientId)
      : null;
    const assignment = await this.repository.assign({
      clientId: eligibility.clientId,
      dietitianId,
      active: true,
      assignedAt: this.now().toISOString(),
      assignedById: actor.uid,
      version: 0,
    });
    if (this.notifications !== null) {
      await this.notifications.clientAssigned(actor, {
        clientId: assignment.clientId,
        dietitianId: assignment.dietitianId,
        assignmentVersion: assignment.version,
        clientName: clientProfile?.name ?? undefined,
      });
    }
    return assignment;
  }

  async dietitianClientCounts(actor: AuthenticatedUser) {
    this.requireAdmin(actor);
    return this.repository.currentClientCounts();
  }

  async assignedClient(actor: AuthenticatedUser, clientIdInput: unknown) {
    if (actor.role !== "dietitian") {
      throw new ClientAssignmentError(
        403,
        "Dietitian access is required to view assigned clients.",
      );
    }
    const clientId = requiredIdentifier(clientIdInput, "Client id");
    const assignment = await this.repository.getCurrent(clientId);
    if (assignment === null || assignment.dietitianId !== actor.uid) {
      throw new ClientAssignmentError(
        403,
        "This client is not currently assigned to you.",
      );
    }
    if (this.clients === null) {
      throw new ClientAssignmentError(503, "Client directory is not configured.");
    }
    const client = await this.clients.getClient(clientId);
    return {
      ...client,
      assignmentStatus: "active" as const,
      assignedAt: assignment.assignedAt,
    };
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

/**
 * Looks up a client profile from Firebase Auth.
 * Used by ClientAssignmentService to resolve the client's name and email
 * before recording an assignment and sending the dietitian notification.
 */
export class FirebaseClientDirectory implements AssignedClientDirectory {
  constructor(private readonly auth: Auth) {}

  async getClient(clientId: string): Promise<AssignedClientProfile> {
    try {
      const user = await this.auth.getUser(clientId);
      return {
        id: user.uid,
        name: user.displayName ?? user.email ?? user.uid,
        email: user.email ?? null,
      };
    } catch {
      throw new ClientAssignmentError(404, "Client not found.");
    }
  }
}
