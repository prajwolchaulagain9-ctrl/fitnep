import { AuthenticatedUser } from "./domain";
import { PrivacyPreferencesRepository, SharingChoice } from "./privacy_preferences_repository";

export interface CurrentAssignedTeam {
  dietitianId: string;
  teamMemberIds: readonly string[];
}

/** Only the active, current assignment grants access; history never does. */
export interface CurrentTeamAssignmentReader {
  getCurrentTeam(clientId: string): Promise<CurrentAssignedTeam | null>;
}

export function currentAssignedTeam(data: Record<string, unknown> | undefined): CurrentAssignedTeam | null {
  const validUid = (value: unknown): value is string => typeof value === "string" &&
    value.length > 0 && value.length <= 128 && !/[\u0000-\u0020\u007f]/.test(value);
  if (data?.active !== true || !validUid(data.dietitian_id)) return null;
  const members = data.team_member_ids === undefined ? [] : data.team_member_ids;
  if (!Array.isArray(members) || !members.every(validUid)) return null;
  return { dietitianId: data.dietitian_id, teamMemberIds: [...new Set(members)] };
}

export class PrivateRecordAuthorizationError extends Error {
  constructor() {
    super("This account cannot access these records.");
  }
}

export class PrivateRecordAccessService {
  constructor(
    private readonly assignments: CurrentTeamAssignmentReader,
    private readonly preferences: Pick<PrivacyPreferencesRepository, "getForClient">,
    private readonly acceptance: { hasCurrentAcceptance(clientId: string): Promise<boolean> },
  ) {}

  async assertCanRead(
    user: AuthenticatedUser,
    clientId: string,
    choice: SharingChoice,
    ownerOnly = false,
  ): Promise<CurrentAssignedTeam | null> {
    if (user.role === "client" && user.uid === clientId) return null;
    if (user.role === "client" || ownerOnly) {
      throw new PrivateRecordAuthorizationError();
    }

    const team = await this.assignments.getCurrentTeam(clientId);
    const assigned = team && (user.role === "dietitian"
      ? team.dietitianId === user.uid
      : (user.role === "staff" || user.role === "admin") && team.teamMemberIds.includes(user.uid));
    if (!assigned || !(await this.acceptance.hasCurrentAcceptance(clientId))) {
      throw new PrivateRecordAuthorizationError();
    }

    const preference = await this.preferences.getForClient(clientId);
    if (!preference[choice]) {
      throw new PrivateRecordAuthorizationError();
    }
    return team;
  }

  async assertCanCollect(
    user: AuthenticatedUser,
    clientId: string,
    choice: SharingChoice,
  ): Promise<void> {
    if (user.role !== "client" || user.uid !== clientId ||
      !(await this.acceptance.hasCurrentAcceptance(clientId))) {
      throw new PrivateRecordAuthorizationError();
    }
    // Manually entered nutrition logs belong to the client even when private.
    if (choice === "shareNutritionRecords") return;
    if (!(await this.preferences.getForClient(clientId))[choice]) {
      throw new PrivateRecordAuthorizationError();
    }
  }
}
