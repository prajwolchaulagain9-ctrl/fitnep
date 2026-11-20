export const sharingFields = {
  shareNutritionRecords: "share_nutrition_records",
  shareMealPhotos: "share_meal_photos",
  shareProgressPhotos: "share_progress_photos",
  shareActivityData: "share_activity_data",
} as const;

export type SharingChoice = keyof typeof sharingFields;
export type SharingChoices = Record<SharingChoice, boolean>;
export const sharingChoices = Object.keys(sharingFields) as SharingChoice[];

export const defaultSharingChoices: Readonly<SharingChoices> = Object.freeze({
  shareNutritionRecords: false,
  shareMealPhotos: false,
  shareProgressPhotos: false,
  shareActivityData: false,
});

export interface PrivacyPreferences extends SharingChoices {
  updatedAt: string | null;
}

export interface PrivacyPreferencesRepository {
  getForClient(clientId: string): Promise<PrivacyPreferences>;

  updateSharing(
    clientId: string,
    changes: Partial<SharingChoices>,
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

  async updateSharing(): Promise<PrivacyPreferences> {
    return this.unavailable();
  }
}
