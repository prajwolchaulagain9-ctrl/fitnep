import { Firestore, Timestamp } from "firebase-admin/firestore";

import {
  PrivacyPreferences,
  PrivacyPreferencesRepository,
} from "./privacy_preferences_repository";

const collectionName = "privacy_preferences";
const fields = {
  shareNutritionRecords: "share_nutrition_records",
  updatedAt: "updated_at",
} as const;

export class FirestorePrivacyPreferencesRepository
  implements PrivacyPreferencesRepository
{
  constructor(private readonly firestore: Firestore) {}

  async getForClient(clientId: string): Promise<PrivacyPreferences> {
    const snapshot = await this.collection.doc(clientId).get();
    if (!snapshot.exists) return defaults;

    return fromData(snapshot.data());
  }

  async setNutritionSharing(
    clientId: string,
    enabled: boolean,
  ): Promise<PrivacyPreferences> {
    const reference = this.collection.doc(clientId);
    const updatedAt = Timestamp.now();
    await reference.set(
      {
        [fields.shareNutritionRecords]: enabled,
        [fields.updatedAt]: updatedAt,
      },
      { merge: true },
    );

    return {
      shareNutritionRecords: enabled,
      updatedAt: updatedAt.toDate().toISOString(),
    };
  }

  private get collection() {
    return this.firestore.collection(collectionName);
  }
}

const defaults: PrivacyPreferences = {
  shareNutritionRecords: false,
  updatedAt: null,
};

function fromData(data: Record<string, unknown> | undefined): PrivacyPreferences {
  const updatedAt = data?.[fields.updatedAt];
  return {
    // Missing or malformed consent is always interpreted as disabled.
    shareNutritionRecords: data?.[fields.shareNutritionRecords] === true,
    updatedAt: updatedAt instanceof Timestamp
      ? updatedAt.toDate().toISOString()
      : null,
  };
}
