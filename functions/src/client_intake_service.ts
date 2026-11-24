import { AuthenticatedUser } from "./domain";

export interface ClientIntakeField {
  label: string;
  value: string;
}

export interface ClientIntakeSection {
  title: string;
  fields: ClientIntakeField[];
}

export interface ClientIntakeRecord {
  clientId: string;
  allergies: string[];
  medicalConditions: string[];
  sections: ClientIntakeSection[];
  submittedAt: string | null;
  updatedAt: string | null;
}

export interface ClientIntakeRepository {
  getForAssignedDietitian(
    clientId: string,
    dietitianId: string,
  ): Promise<ClientIntakeRecord>;
}

export class ClientIntakeError extends Error {
  constructor(
    readonly statusCode: 400 | 403 | 404 | 503,
    message: string,
  ) {
    super(message);
    this.name = "ClientIntakeError";
  }
}

export class ClientIntakeService {
  constructor(private readonly repository: ClientIntakeRepository) {}

  async getAssignedClientIntake(
    actor: AuthenticatedUser,
    clientIdInput: unknown,
  ): Promise<ClientIntakeRecord> {
    if (actor.role !== "dietitian") {
      throw new ClientIntakeError(
        403,
        "Dietitian access is required to view client intake forms.",
      );
    }
    const clientId = requiredIdentifier(clientIdInput);
    return this.repository.getForAssignedDietitian(clientId, actor.uid);
  }
}

function requiredIdentifier(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new ClientIntakeError(400, "Client id is invalid.");
  }
  return value;
}
