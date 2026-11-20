import { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";

import {
  PrivacyPreferences,
  PrivacyPreferencesRepository,
  SharingChoices,
  defaultSharingChoices,
  sharingChoices,
  sharingFields,
} from "./privacy_preferences_repository";

export class FirestorePrivacyPreferencesRepository
  implements PrivacyPreferencesRepository
{
  constructor(private readonly firestore: Firestore) {}

  async getForClient(clientId: string, transaction?: Transaction): Promise<PrivacyPreferences> {
    const reference = this.firestore.collection("privacy_preferences").doc(clientId);
    const snapshot = transaction ? await transaction.get(reference) : await reference.get();
    return fromData(snapshot.data());
  }

  async updateSharing(
    clientId: string,
    changes: Partial<SharingChoices>,
  ): Promise<PrivacyPreferences> {
    const reference = this.firestore.collection("privacy_preferences").doc(clientId);
    return this.firestore.runTransaction(async (transaction) => {
      const current = fromData((await transaction.get(reference)).data());
      const updatedAt = Timestamp.now();
      const update: Record<string, boolean | Timestamp> = { updated_at: updatedAt };
      for (const choice of sharingChoices) {
        const value = changes[choice];
        if (value !== undefined) update[sharingFields[choice]] = value;
      }
      transaction.set(reference, update, { merge: true });
      return { ...current, ...changes, updatedAt: updatedAt.toDate().toISOString() };
    });
  }
}

function fromData(data: Record<string, unknown> | undefined): PrivacyPreferences {
  const choices = { ...defaultSharingChoices };
  for (const choice of sharingChoices) {
    choices[choice] = data?.[sharingFields[choice]] === true;
  }
  const updatedAt = data?.updated_at;
  return {
    ...choices,
    updatedAt: updatedAt instanceof Timestamp
      ? updatedAt.toDate().toISOString()
      : null,
  };
}
