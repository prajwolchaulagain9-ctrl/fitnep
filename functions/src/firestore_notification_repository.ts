import { createHash } from "node:crypto";

import {
  DocumentData,
  DocumentSnapshot,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import {
  CreateNotificationResult,
  NewNotification,
  NotificationRecord,
  notificationTypes,
  NotificationType,
} from "./domain";
import { NotificationRepository } from "./notification_repository";

const collectionName = "notifications";
const maxListSize = 250;
const batchSize = 400;
const fields = {
  recipientId: "recipient_id",
  referenceId: "reference_id",
  isRead: "is_read",
  createdAt: "created_at",
  eventKey: "event_key",
} as const;

export class FirestoreNotificationRepository
  implements NotificationRepository
{
  constructor(private readonly firestore: Firestore) {}

  async listForRecipient(recipientId: string): Promise<NotificationRecord[]> {
    const snapshot = await this.collection
      .where(fields.recipientId, "==", recipientId)
      .orderBy(fields.createdAt, "desc")
      .limit(maxListSize)
      .get();
    return snapshot.docs.map(fromSnapshot);
  }

  async getForRecipient(
    notificationId: string,
    recipientId: string,
  ): Promise<NotificationRecord | null> {
    const snapshot = await this.collection.doc(notificationId).get();
    if (
      !snapshot.exists ||
      snapshot.get(fields.recipientId) !== recipientId
    ) {
      return null;
    }
    return fromSnapshot(snapshot);
  }

  markReadForRecipient(
    notificationId: string,
    recipientId: string,
  ): Promise<NotificationRecord | null> {
    const reference = this.collection.doc(notificationId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (
        !snapshot.exists ||
        snapshot.get(fields.recipientId) !== recipientId
      ) {
        return null;
      }
      if (!snapshot.get(fields.isRead)) {
        transaction.update(reference, { [fields.isRead]: true });
      }
      return { ...fromSnapshot(snapshot), isRead: true };
    });
  }

  async markAllReadForRecipient(recipientId: string): Promise<number> {
    let updatedCount = 0;

    while (true) {
      const snapshot = await this.collection
        .where(fields.recipientId, "==", recipientId)
        .where(fields.isRead, "==", false)
        .limit(batchSize)
        .get();
      if (snapshot.empty) return updatedCount;

      const batch = this.firestore.batch();
      for (const document of snapshot.docs) {
        batch.update(document.ref, { [fields.isRead]: true });
      }
      await batch.commit();
      updatedCount += snapshot.size;
    }
  }

  createIfAbsent(
    input: NewNotification,
  ): Promise<CreateNotificationResult> {
    return this.firestore.runTransaction(async transaction =>
      (await this.createManyInTransaction(transaction, [input]))[0]!);
  }

  async createManyInTransaction(transaction: Transaction, inputs: NewNotification[]): Promise<CreateNotificationResult[]> {
    const references = inputs.map(input => this.collection.doc(documentIdForEvent(input.eventKey)));
    const snapshots = await Promise.all(references.map(reference => transaction.get(reference)));
    return inputs.map((input, index) => {
      const reference = references[index]!;
      const snapshot = snapshots[index]!;
      if (snapshot.exists) {
        const existing = fromSnapshot(snapshot);
        if (existing.eventKey !== input.eventKey) {
          throw new Error("Notification event-key hash collision detected.");
        }
        return { notification: existing, created: false };
      }

      const createdAt = parseCreatedAt(input.createdAt);
      const record: NotificationRecord = {
        ...input,
        id: reference.id,
        isRead: false,
        createdAt: createdAt.toDate().toISOString(),
      };
      transaction.create(reference, {
        [fields.recipientId]: record.recipientId,
        title: record.title,
        message: record.message,
        type: record.type,
        [fields.referenceId]: record.referenceId,
        [fields.isRead]: false,
        [fields.createdAt]: createdAt,
        [fields.eventKey]: record.eventKey,
      });
      return { notification: record, created: true };
    });
  }

  private get collection() {
    return this.firestore.collection(collectionName);
  }
}

function documentIdForEvent(eventKey: string): string {
  return createHash("sha256").update(eventKey).digest("hex");
}

function parseCreatedAt(value: string | undefined): Timestamp {
  const date = value === undefined ? new Date() : new Date(value);
  if (Number.isNaN(date.getTime())) {
    throw new Error("Notification createdAt is invalid.");
  }
  return Timestamp.fromDate(date);
}

function fromSnapshot(
  snapshot:
    | QueryDocumentSnapshot<DocumentData>
    | DocumentSnapshot<DocumentData>,
): NotificationRecord {
  const data = snapshot.data();
  if (data === undefined) throw new Error("Notification record is missing.");

  const type = requiredType(data.type);
  const createdAt = data[fields.createdAt];
  if (!(createdAt instanceof Timestamp)) {
    throw new Error("Notification createdAt is invalid.");
  }

  return {
    id: snapshot.id,
    recipientId: requiredString(data[fields.recipientId], fields.recipientId),
    title: requiredString(data.title, "title"),
    message: requiredString(data.message, "message"),
    type,
    referenceId: requiredString(data[fields.referenceId], fields.referenceId),
    isRead: data[fields.isRead] === true,
    createdAt: createdAt.toDate().toISOString(),
    eventKey: requiredString(data[fields.eventKey], fields.eventKey),
  };
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Notification ${field} is invalid.`);
  }
  return value;
}

function requiredType(value: unknown): NotificationType {
  if (
    typeof value !== "string" ||
    !notificationTypes.includes(value as NotificationType)
  ) {
    throw new Error("Notification type is invalid.");
  }
  return value as NotificationType;
}
