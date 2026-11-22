import { AuthenticatedUser } from "./domain";
import { requirePermission } from "./authorization_policy";
import {
  PrivacyPreferences,
  PrivacyPreferencesRepository,
  SharingChoices,
  sharingChoices,
  sharingFields,
} from "./privacy_preferences_repository";

export class PrivacyPreferencesAuthorizationError extends Error {
  constructor() {
    super("Only the client can manage their privacy preferences.");
    this.name = "PrivacyPreferencesAuthorizationError";
  }
}

export class InvalidPrivacyPreferencesError extends Error {
  constructor() {
    super("Supply one or more supported sharing choices as booleans.");
    this.name = "InvalidPrivacyPreferencesError";
  }
}

export class PrivacyPreferencesService {
  constructor(private readonly repository: PrivacyPreferencesRepository) {}

  getForUser(user: AuthenticatedUser): Promise<PrivacyPreferences> {
    requireClient(user);
    return this.repository.getForClient(user.uid);
  }

  updateSharing(
    user: AuthenticatedUser,
    body: unknown,
  ): Promise<PrivacyPreferences> {
    requireClient(user);
    if (typeof body !== "object" || body === null || Array.isArray(body)) {
      throw new InvalidPrivacyPreferencesError();
    }
    const submitted = Object.entries(body);
    if (submitted.length === 0) throw new InvalidPrivacyPreferencesError();

    const changes: Partial<SharingChoices> = {};
    for (const [key, value] of submitted) {
      const choice = sharingChoices.find((choice) => sharingFields[choice] === key);
      if (choice === undefined || typeof value !== "boolean") {
        throw new InvalidPrivacyPreferencesError();
      }
      changes[choice] = value;
    }
    return this.repository.updateSharing(user.uid, changes);
  }
}

function requireClient(user: AuthenticatedUser): void {
  requirePermission(user.role, "manage_own_privacy");
}
