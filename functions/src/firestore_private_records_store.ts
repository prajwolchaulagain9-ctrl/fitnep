import { DocumentReference, DocumentSnapshot, FieldPath, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";
import { ClientIntakeError } from "./client_intake_service";

import { AuditWriter, AuditUnavailableError, FirestoreAuditWriter } from "./audit";
import { AuditedHealthReadService, HealthReadTarget } from "./audited_health_reads";
import { AuthenticatedUser } from "./domain";
import { accountFrom, accountMatchesActor, assignmentIncludesActor, getCurrentAssignment } from "./account_service";
import { PermissionDeniedError } from "./authorization_policy";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { PrivateRecordAccessService, PrivateRecordAuthorizationError } from "./nutrition_record_access_service";
import { FirestorePrivacyAcceptanceStore } from "./privacy_policy_acceptance";
import { isPhotoMimeType, PhotoMimeType, PrivatePhotoStorage } from "./cloudinary_photo_storage";
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
  photoContentTypes,
  recordSharingChoices,
} from "./private_records";

type PendingPhoto = {
  client_id: string;
  category: RecordCategory;
  content_type: PhotoMimeType;
  recorded_at: Timestamp;
};

export class FirestorePrivateRecordsStore implements PrivateRecordsStore {
  constructor(
    private readonly firestore: Firestore,
    private readonly preferences: FirestorePrivacyPreferencesRepository,
    private readonly audit: Pick<AuditWriter, "appendInTransaction"> = new FirestoreAuditWriter(firestore),
    private readonly photoStorage?: PrivatePhotoStorage,
  ) {}

  list(actor: AuthenticatedUser, clientId: string, category: RecordCategory, after?: string, correlationId?: string): Promise<PrivateRecord[]> {
    return this.auditedRead(actor, { clientId, category }, correlationId, async (transaction) => {
      const ordered = this.records(clientId, category).orderBy(FieldPath.documentId());
      const query = (after === undefined ? ordered : ordered.startAfter(after))
        .select("recorded_at", "details").limit(50);
      const result = await transaction.get(query);
      return { data: result.docs.map(doc => this.toRecord(doc, category)), recordIds: result.docs.map(doc => doc.id) };
    });
  }

  read(actor: AuthenticatedUser, clientId: string, category: RecordCategory, id: string, correlationId?: string): Promise<PrivateRecord> {
    return this.auditedRead(actor, { clientId, category, recordId: id }, correlationId, async (transaction) => {
      const record = await transaction.get(this.records(clientId, category).doc(id));
      if (!record.exists) throw new PrivateRecordsError(404, "Record not found.");
      return { data: this.toRecord(record, category) };
    });
  }

  collect(actor: AuthenticatedUser, clientId: string, category: RecordCategory, body: unknown): Promise<PrivateRecord> {
    if (this.photoStorage && isPhotoCategory(category)) {
      return this.collectStoredPhoto(this.photoStorage, actor, clientId, category, body);
    }
    return this.firestore.runTransaction(async (transaction) => {
      await this.assertCurrentActor(transaction, actor);
      // Reading consent and writing the entry in one transaction makes collection
      // and consent withdrawal serialize against the same Firestore document.
      await this.access(transaction, actor).assertCanCollect(actor, clientId, recordSharingChoices[category]);
      const record = parseRecord(category, body);
      const reference = this.records(clientId, category).doc();
      const recordedAt = Timestamp.now();
      transaction.create(reference, { ...record, recorded_at: recordedAt });
      return {
        id: reference.id, recorded_at: recordedAt.toDate().toISOString(), details: record.details,
      };
    });
  }

  async readPhoto(actor: AuthenticatedUser, clientId: string, category: RecordCategory, id: string, correlationId?: string): Promise<PrivatePhoto> {
    if (!isPhotoCategory(category)) {
      throw new PrivateRecordsError(404, "Photo not found.");
    }
    const photo = await this.auditedRead<PrivatePhoto | { contentType: PhotoMimeType }>(
      actor, { clientId, category, recordId: id }, correlationId, async (transaction) => {
      const snapshot = await transaction.get(this.records(clientId, category).doc(id));
      if (snapshot.get("photo_storage") === "cloudinary") {
        const contentType: unknown = snapshot.get("details.content_type");
        if (!this.photoStorage || !isPhotoMimeType(contentType)) throw unavailablePhoto();
        return { data: { contentType } };
      }
      const bytes: unknown = snapshot.get("photo");
      const contentType = Buffer.isBuffer(bytes) ? photoContentType(bytes) : null;
      if (!Buffer.isBuffer(bytes) || !contentType) {
        throw new PrivateRecordsError(404, "Photo not found.");
      }
      return { data: { bytes, contentType } };
    });
    if ("bytes" in photo) return photo;
    // Fetch only after the existing consent, assignment and audit transaction.
    const bytes = await this.photoStorage!.read(id, photo.contentType);
    return { bytes, contentType: photo.contentType };
  }

  private async collectStoredPhoto(
    storage: PrivatePhotoStorage, actor: AuthenticatedUser, clientId: string,
    category: RecordCategory, body: unknown,
  ): Promise<PrivateRecord> {
    const ref = this.firestore.collection("private_photo_uploads").doc();
    const { reservation, bytes } = await this.firestore.runTransaction(async transaction => {
      await this.assertCurrentActor(transaction, actor);
      await this.access(transaction, actor).assertCanCollect(actor, clientId, recordSharingChoices[category]);
      const photo = parseRecord(category, body);
      const contentType = photo.details.content_type;
      if (!photo.photo || !isPhotoMimeType(contentType)) throw unavailablePhoto();
      const reservation: PendingPhoto = {
        client_id: clientId, category, content_type: contentType, recorded_at: Timestamp.now(),
      };
      // The reservation is private and invisible to the record list until upload completes.
      transaction.create(ref, {
        ...reservation, retry_at: Timestamp.fromMillis(Date.now() + 5 * 60_000),
      });
      return { reservation, bytes: photo.photo };
    });
    try {
      await storage.write(ref.id, bytes, reservation.content_type);
      return await this.finishPhotoUpload(ref, reservation);
    } catch {
      // The host can finish a successfully uploaded photo after a crash or lost response.
      throw unavailablePhoto();
    }
  }

  async recoverPhotoUploads(): Promise<void> {
    const storage = this.photoStorage;
    if (!storage) return;
    const now = Date.now();
    const pending = await this.firestore.collection("private_photo_uploads")
      .where("retry_at", "<=", Timestamp.fromMillis(now)).orderBy("retry_at").limit(5).get();
    await Promise.all(pending.docs.map(async snapshot => {
      const data = snapshot.data();
      if (typeof data.client_id !== "string" || !isPhotoCategory(data.category) ||
          !isPhotoMimeType(data.content_type) || !(data.recorded_at instanceof Timestamp)) return;
      const reservation = data as PendingPhoto;
      try {
        await storage.read(snapshot.id, reservation.content_type);
        await this.finishPhotoUpload(snapshot.ref, reservation);
      } catch (error) {
        await this.firestore.runTransaction(async transaction => {
          if (!(await transaction.get(snapshot.ref)).exists) return;
          if (error instanceof PrivateRecordsError && error.status === 404 &&
              now - reservation.recorded_at.toMillis() > 60 * 60_000) {
            transaction.delete(snapshot.ref);
          } else {
            transaction.update(snapshot.ref, { retry_at: Timestamp.fromMillis(now + 15 * 60_000) });
          }
        });
      }
    }));
  }

  private finishPhotoUpload(pending: DocumentReference, reservation: PendingPhoto): Promise<PrivateRecord> {
    const record = this.records(reservation.client_id, reservation.category).doc(pending.id);
    return this.firestore.runTransaction(async transaction => {
      const staged = await transaction.get(pending);
      if (!staged.exists) {
        const saved = await transaction.get(record);
        if (!saved.exists) throw unavailablePhoto();
        return this.toRecord(saved, reservation.category);
      }
      const details = { content_type: reservation.content_type };
      transaction.create(record, {
        details,
        recorded_at: reservation.recorded_at,
        photo_storage: "cloudinary",
      });
      transaction.delete(pending);
      return { id: record.id, details, recorded_at: reservation.recorded_at.toDate().toISOString() };
    });
  }

  private records(clientId: string, category: RecordCategory) {
    return this.firestore.collection("client_records").doc(clientId).collection(category);
  }

  readResource<T>(actor: AuthenticatedUser, target: HealthReadTarget,
    load: (transaction: Transaction) => Promise<{ data: T; recordIds?: readonly string[] }>, correlationId?: string): Promise<T> {
    return this.auditedRead(actor, target, correlationId, load);
  }

  private auditedRead<T>(actor: AuthenticatedUser, target: HealthReadTarget, correlationId: string | undefined,
    load: (transaction: Transaction) => Promise<{ data: T; recordIds?: readonly string[] }>): Promise<T> {
    return this.firestore.runTransaction(async transaction => {
      await this.assertCurrentActor(transaction, actor);
      return new AuditedHealthReadService(this.access(transaction, actor), this.audit)
        .read(transaction, actor, target, correlationId ?? randomUUID(), () => load(transaction));
    }).catch(error => {
      if (error instanceof PrivateRecordAuthorizationError || error instanceof PrivateRecordsError ||
        error instanceof AuditUnavailableError || error instanceof ClientIntakeError) throw error;
      if (error instanceof PermissionDeniedError) throw new PrivateRecordAuthorizationError(error.reason);
      throw new PrivateRecordsError(503, "Private record storage is temporarily unavailable.");
    });
  }

  private async assertCurrentActor(transaction: Transaction, actor: AuthenticatedUser) {
    const current = accountFrom(actor.uid,
      (await transaction.get(this.firestore.collection("users").doc(actor.uid))).data());
    if (!accountMatchesActor(current, actor)) throw new PrivateRecordAuthorizationError();
  }

  private toRecord(snapshot: DocumentSnapshot, category: RecordCategory): PrivateRecord {
    const details = snapshot.get("details") as RecordDetails | undefined;
    const recordedAt = snapshot.get("recorded_at");
    if (!details || !(recordedAt instanceof Timestamp)) {
      throw new PrivateRecordsError(503, "Private record storage is temporarily unavailable.");
    }
    // Project the permitted fields even if a later producer stores extra metadata.
    let safeDetails: RecordDetails;
    if (isPhotoCategory(category)) {
      const contentType = details.content_type;
      if (typeof contentType !== "string" || !photoContentTypes.includes(contentType)) {
        throw new PrivateRecordsError(503, "Private record storage is temporarily unavailable.");
      }
      safeDetails = { content_type: contentType };
    } else {
      safeDetails = parseRecord(category, details).details;
    }
    return { id: snapshot.id, recorded_at: recordedAt.toDate().toISOString(), details: safeDetails };
  }

  private access(transaction: Transaction, actor: AuthenticatedUser): PrivateRecordAccessService {
    return new PrivateRecordAccessService({
      getCurrentTeam: async (clientId) => {
        const assignment = await getCurrentAssignment(this.firestore, clientId, transaction);
        return assignment && assignmentIncludesActor(actor, assignment) ? assignment.team : null;
      },
    }, {
      getForClient: (clientId) => this.preferences.getForClient(clientId, transaction),
    }, {
      hasCurrentAcceptance: clientId => new FirestorePrivacyAcceptanceStore(this.firestore)
        .hasCurrentAcceptance(clientId, transaction),
    });
  }
}

function unavailablePhoto() {
  return new PrivateRecordsError(503, "Photo storage is temporarily unavailable.");
}
