import { AuthenticatedUser } from "./domain";
import { PrivacyPreferencesRepository, SharingChoice } from "./privacy_preferences_repository";
import { PermissionDeniedError } from "./authorization_policy";

/** Supplies the current assignment from trusted server-side assignment data. */
export interface CurrentDietitianAssignmentReader {
  getCurrentDietitianId(clientId: string): Promise<string | null>;
}

export class PrivateRecordAuthorizationError extends PermissionDeniedError {
  constructor(reason = "The account cannot access these records.") {
    super(reason);
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
      throw new PrivateRecordAuthorizationError("Private records require the owner or an assigned dietitian.");
    }

    const assignedDietitianId = await this.assignments.getCurrentDietitianId(
      clientId,
    );
    if (assignedDietitianId !== user.uid) {
      throw new PrivateRecordAuthorizationError("The client is outside the current dietitian assignment.");
    }

    const preference = await this.preferences.getForClient(clientId);
    if (!preference[choice]) {
      throw new PrivateRecordAuthorizationError("The client has not enabled sharing for this category.");
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
