import { FieldPath, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";

import { AuthenticatedUser } from "./domain";
import { accountFrom } from "./account_service";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { PrivateRecordAccessService } from "./nutrition_record_access_service";
import {
  PrivatePhoto,
  PrivateRecord,
  PrivateRecordsError,
  PrivateRecordsStore,
  RecordCategory,
  RecordDetails,
  isPhotoCategory,
  parseRecord,
  photoContentType,
  recordSharingChoices,
} from "./private_records";

export class FirestorePrivateRecordsStore implements PrivateRecordsStore {
  constructor(
    private readonly firestore: Firestore,
    private readonly preferences: FirestorePrivacyPreferencesRepository,
  ) {}

  list(actor: AuthenticatedUser, clientId: string, category: RecordCategory, after?: string): Promise<PrivateRecord[]> {
    return this.firestore.runTransaction(async (transaction) => {
      await this.access(transaction, actor.roleRevision).assertCanRead(actor, clientId, recordSharingChoices[category]);
      const ordered = this.records(clientId, category).orderBy(FieldPath.documentId());
      const query = (after === undefined ? ordered : ordered.startAfter(after))
        .select("recorded_at", "details").limit(50);
      const result = await transaction.get(query);
      return result.docs.map((doc) => ({
        id: doc.id,
        recorded_at: (doc.get("recorded_at") as Timestamp).toDate().toISOString(),
        details: doc.get("details") as RecordDetails,
      }));
    });
  }

  collect(actor: AuthenticatedUser, clientId: string, category: RecordCategory, body: unknown): Promise<PrivateRecord> {
    return this.firestore.runTransaction(async (transaction) => {
      // Reading consent and writing the entry in one transaction makes collection
      // and consent withdrawal serialize against the same Firestore document.
      await this.access(transaction, actor.roleRevision).assertCanCollect(actor, clientId, recordSharingChoices[category]);
      const record = parseRecord(category, body);
      const reference = this.records(clientId, category).doc();
      const recordedAt = Timestamp.now();
      transaction.create(reference, { ...record, recorded_at: recordedAt });
      return {
        id: reference.id, recorded_at: recordedAt.toDate().toISOString(), details: record.details,
      };
    });
  }

  readPhoto(actor: AuthenticatedUser, clientId: string, category: RecordCategory, id: string): Promise<PrivatePhoto> {
    if (!isPhotoCategory(category)) {
      throw new PrivateRecordsError(404, "Photo not found.");
    }
    return this.firestore.runTransaction(async (transaction) => {
      await this.access(transaction, actor.roleRevision).assertCanRead(actor, clientId, recordSharingChoices[category]);
      const snapshot = await transaction.get(this.records(clientId, category).doc(id));
      const bytes: unknown = snapshot.get("photo");
      const contentType = Buffer.isBuffer(bytes) ? photoContentType(bytes) : null;
      if (!Buffer.isBuffer(bytes) || !contentType) {
        throw new PrivateRecordsError(404, "Photo not found.");
      }
      return { bytes, contentType };
    });
  }

  private records(clientId: string, category: RecordCategory) {
    return this.firestore.collection("client_records").doc(clientId).collection(category);
  }

  private access(transaction: Transaction, thisActorRevision?: number): PrivateRecordAccessService {
    return new PrivateRecordAccessService({
      getCurrentDietitianId: async (clientId) => {
        const reference = this.firestore.collection("client_assignments").doc(clientId);
        const assignment = (await transaction.get(reference)).data();
        const client = accountFrom(clientId, (await transaction.get(this.firestore.collection("users").doc(clientId))).data());
        if (client.role !== "client" || client.account_status !== "active") return null;
        if ((assignment?.client_role_revision ?? 0) !== client.role_revision) return null;
        return assignment?.active === true &&
          (assignment.dietitian_role_revision ?? 0) === (thisActorRevision ?? 0) &&
          typeof assignment.dietitian_id === "string"
          ? assignment.dietitian_id : null;
      },
    }, {
      getForClient: (clientId) => this.preferences.getForClient(clientId, transaction),
    });
  }
}
