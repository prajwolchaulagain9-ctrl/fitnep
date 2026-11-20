import { AuthenticatedUser } from "./domain";
import { PrivacyPreferencesRepository } from "./privacy_preferences_repository";

/** Supplies the current assignment from trusted server-side assignment data. */
export interface CurrentDietitianAssignmentReader {
  getCurrentDietitianId(clientId: string): Promise<string | null>;
}

export class NutritionRecordsAuthorizationError extends Error {
  constructor() {
    super("This account cannot access these nutrition records.");
    this.name = "NutritionRecordsAuthorizationError";
  }
}

export class AssignmentStorageNotConfiguredError extends Error {
  constructor() {
    super("Client assignment storage is not configured.");
    this.name = "AssignmentStorageNotConfiguredError";
  }
}

/**
 * Shared authorization gate for nutrition-record read handlers. Client reads
 * are owner-scoped; a dietitian must be the current assignee and have consent.
 */
export class NutritionRecordAccessService {
  constructor(
    private readonly assignments: CurrentDietitianAssignmentReader,
    private readonly preferences: PrivacyPreferencesRepository,
  ) {}

  async assertCanRead(
    user: AuthenticatedUser,
    clientId: string,
  ): Promise<void> {
    if (user.role === "client" && user.uid === clientId) return;
    if (user.role !== "dietitian") {
      throw new NutritionRecordsAuthorizationError();
    }

    const assignedDietitianId = await this.assignments.getCurrentDietitianId(
      clientId,
    );
    if (assignedDietitianId !== user.uid) {
      throw new NutritionRecordsAuthorizationError();
    }

    const preference = await this.preferences.getForClient(clientId);
    if (!preference.shareNutritionRecords) {
      throw new NutritionRecordsAuthorizationError();
    }
  }
}

/** Fail closed until the assignment feature supplies its trusted reader. */
export class UnconfiguredCurrentDietitianAssignmentReader
  implements CurrentDietitianAssignmentReader
{
  async getCurrentDietitianId(): Promise<string | null> {
    throw new AssignmentStorageNotConfiguredError();
  }
}
