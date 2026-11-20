import { AuthenticatedUser } from "./domain";
import { PrivacyPreferencesRepository, SharingChoice } from "./privacy_preferences_repository";

/** Supplies the current assignment from trusted server-side assignment data. */
export interface CurrentDietitianAssignmentReader {
  getCurrentDietitianId(clientId: string): Promise<string | null>;
}

export class PrivateRecordAuthorizationError extends Error {
  constructor() {
    super("This account cannot access these records.");
  }
}

export class PrivateRecordAccessService {
  constructor(
    private readonly assignments: CurrentDietitianAssignmentReader,
    private readonly preferences: Pick<PrivacyPreferencesRepository, "getForClient">,
  ) {}

  async assertCanRead(
    user: AuthenticatedUser,
    clientId: string,
    choice: SharingChoice,
  ): Promise<void> {
    if (user.role === "client" && user.uid === clientId) return;
    if (user.role !== "dietitian") {
      throw new PrivateRecordAuthorizationError();
    }

    const assignedDietitianId = await this.assignments.getCurrentDietitianId(
      clientId,
    );
    if (assignedDietitianId !== user.uid) {
      throw new PrivateRecordAuthorizationError();
    }

    const preference = await this.preferences.getForClient(clientId);
    if (!preference[choice]) {
      throw new PrivateRecordAuthorizationError();
    }
  }

  async assertCanCollect(
    user: AuthenticatedUser,
    clientId: string,
    choice: SharingChoice,
  ): Promise<void> {
    if (user.role !== "client" || user.uid !== clientId) {
      throw new PrivateRecordAuthorizationError();
    }
    // Manually entered nutrition logs belong to the client even when private.
    if (choice === "shareNutritionRecords") return;
    if (!(await this.preferences.getForClient(clientId))[choice]) {
      throw new PrivateRecordAuthorizationError();
    }
  }
}
