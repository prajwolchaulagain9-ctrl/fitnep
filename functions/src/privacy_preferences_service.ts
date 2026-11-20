import { AuthenticatedUser } from "./domain";
import {
  PrivacyPreferences,
  PrivacyPreferencesRepository,
} from "./privacy_preferences_repository";

export class PrivacyPreferencesAuthorizationError extends Error {
  constructor() {
    super("Only the client can manage their privacy preferences.");
    this.name = "PrivacyPreferencesAuthorizationError";
  }
}

export class InvalidPrivacyPreferencesError extends Error {
  constructor() {
    super("share_nutrition_records must be a boolean.");
    this.name = "InvalidPrivacyPreferencesError";
  }
}

export class PrivacyPreferencesService {
  constructor(private readonly repository: PrivacyPreferencesRepository) {}

  getForUser(user: AuthenticatedUser): Promise<PrivacyPreferences> {
    requireClient(user);
    return this.repository.getForClient(user.uid);
  }

  setNutritionSharing(
    user: AuthenticatedUser,
    enabled: unknown,
  ): Promise<PrivacyPreferences> {
    requireClient(user);
    if (typeof enabled !== "boolean") {
      throw new InvalidPrivacyPreferencesError();
    }
    return this.repository.setNutritionSharing(user.uid, enabled);
  }
}

function requireClient(user: AuthenticatedUser): void {
  if (user.role !== "client") {
    throw new PrivacyPreferencesAuthorizationError();
  }
}
