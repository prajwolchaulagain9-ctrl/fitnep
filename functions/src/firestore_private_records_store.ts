import { DocumentSnapshot, FieldPath, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";

import { AuditWriter, AuditUnavailableError, FirestoreAuditWriter } from "./audit";
import { AuditedHealthReadService, HealthReadTarget } from "./audited_health_reads";
import { AuthenticatedUser } from "./domain";
import { accountFrom } from "./account_service";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { currentAssignedTeam, PrivateRecordAccessService, PrivateRecordAuthorizationError } from "./nutrition_record_access_service";
import { FirestorePrivacyAcceptanceStore } from "./privacy_policy_acceptance";
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

export class FirestorePrivateRecordsStore implements PrivateRecordsStore {
  constructor(
    private readonly firestore: Firestore,
    private readonly preferences: FirestorePrivacyPreferencesRepository,
    private readonly audit: Pick<AuditWriter, "appendInTransaction"> = new FirestoreAuditWriter(firestore),
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
    return this.firestore.runTransaction(async (transaction) => {
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

  readPhoto(actor: AuthenticatedUser, clientId: string, category: RecordCategory, id: string, correlationId?: string): Promise<PrivatePhoto> {
    if (!isPhotoCategory(category)) {
      throw new PrivateRecordsError(404, "Photo not found.");
    }
    return this.auditedRead(actor, { clientId, category, recordId: id }, correlationId, async (transaction) => {
      const snapshot = await transaction.get(this.records(clientId, category).doc(id));
      const bytes: unknown = snapshot.get("photo");
      const contentType = Buffer.isBuffer(bytes) ? photoContentType(bytes) : null;
      if (!Buffer.isBuffer(bytes) || !contentType) {
        throw new PrivateRecordsError(404, "Photo not found.");
      }
      return { data: { bytes, contentType } };
    });
  }

  private records(clientId: string, category: RecordCategory) {
    return this.firestore.collection("client_records").doc(clientId).collection(category);
  }

  private auditedRead<T>(actor: AuthenticatedUser, target: HealthReadTarget, correlationId: string | undefined,
    load: (transaction: Transaction) => Promise<{ data: T; recordIds?: readonly string[] }>): Promise<T> {
    return this.firestore.runTransaction(transaction =>
      new AuditedHealthReadService(this.access(transaction, actor), this.audit)
        .read(transaction, actor, target, correlationId ?? randomUUID(), () => load(transaction)),
    ).catch(error => {
      if (error instanceof PrivateRecordAuthorizationError || error instanceof PrivateRecordsError ||
        error instanceof AuditUnavailableError) throw error;
      throw new PrivateRecordsError(503, "Private record storage is temporarily unavailable.");
    });
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
        const reference = this.firestore.collection("client_assignments").doc(clientId);
        const assignment = (await transaction.get(reference)).data();
        const team = currentAssignedTeam(assignment);
        if (!team) return null;
        const client = accountFrom(clientId, (await transaction.get(this.firestore.collection("users").doc(clientId))).data());
        if (client.role !== "client" || client.account_status !== "active" ||
          (assignment?.client_role_revision ?? 0) !== client.role_revision) return null;
        const expectedRevision = actor.role === "dietitian" ? assignment?.dietitian_role_revision :
          assignment?.team_member_role_revisions?.[actor.uid] ?? assignment?.staff_role_revisions?.[actor.uid];
        if ((expectedRevision ?? 0) !== (actor.roleRevision ?? 0)) return null;
        return team;
      },
    }, {
      getForClient: (clientId) => this.preferences.getForClient(clientId, transaction),
    }, {
      hasCurrentAcceptance: clientId => new FirestorePrivacyAcceptanceStore(this.firestore)
        .hasCurrentAcceptance(clientId, transaction),
    });
  }
}
