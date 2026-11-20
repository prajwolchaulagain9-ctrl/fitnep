export interface PrivacyPreferences {
  shareNutritionRecords: boolean;
  updatedAt: string | null;
}

export interface PrivacyPreferencesRepository {
  getForClient(clientId: string): Promise<PrivacyPreferences>;

  setNutritionSharing(
    clientId: string,
    enabled: boolean,
  ): Promise<PrivacyPreferences>;
}

export class PrivacyPreferencesStorageNotConfiguredError extends Error {
  constructor() {
    super("Privacy preferences storage is not configured.");
    this.name = "PrivacyPreferencesStorageNotConfiguredError";
  }
}

export class UnconfiguredPrivacyPreferencesRepository
  implements PrivacyPreferencesRepository
{
  private unavailable(): never {
    throw new PrivacyPreferencesStorageNotConfiguredError();
  }

  async getForClient(): Promise<PrivacyPreferences> {
    return this.unavailable();
  }

  async setNutritionSharing(): Promise<PrivacyPreferences> {
    return this.unavailable();
  }
}
