import {
  CreateNotificationResult,
  NewNotification,
  NotificationRecord,
} from "../src/domain";
import { NotificationRepository } from "../src/notification_repository";

export class InMemoryNotificationRepository
  implements NotificationRepository
{
  private records: NotificationRecord[];

  constructor(seed: NotificationRecord[] = []) {
    this.records = seed.map(copyNotification);
  }

  async listForRecipient(recipientId: string): Promise<NotificationRecord[]> {
    return this.records
      .filter((notification) => notification.recipientId === recipientId)
      .map(copyNotification);
  }

  async getForRecipient(
    notificationId: string,
    recipientId: string,
  ): Promise<NotificationRecord | null> {
    const notification = this.records.find(
      (candidate) =>
        candidate.id === notificationId &&
        candidate.recipientId === recipientId,
    );
    return notification === undefined ? null : copyNotification(notification);
  }

  async markReadForRecipient(
    notificationId: string,
    recipientId: string,
  ): Promise<NotificationRecord | null> {
    const index = this.records.findIndex(
      (candidate) =>
        candidate.id === notificationId &&
        candidate.recipientId === recipientId,
    );
    if (index < 0) return null;
    const existing = this.records[index]!;
    const updated = { ...existing, isRead: true };
    this.records[index] = updated;
    return copyNotification(updated);
  }

  async markAllReadForRecipient(recipientId: string): Promise<number> {
    let updatedCount = 0;
    this.records = this.records.map((notification) => {
      if (notification.recipientId !== recipientId || notification.isRead) {
        return notification;
      }
      updatedCount++;
      return { ...notification, isRead: true };
    });
    return updatedCount;
  }

  async createIfAbsent(
    input: NewNotification,
  ): Promise<CreateNotificationResult> {
    const existing = this.records.find(
      (notification) => notification.eventKey === input.eventKey,
    );
    if (existing !== undefined) {
      return { notification: copyNotification(existing), created: false };
    }

    const notification: NotificationRecord = {
      ...input,
      isRead: false,
      createdAt: input.createdAt ?? new Date().toISOString(),
    };
    this.records.push(notification);
    return { notification: copyNotification(notification), created: true };
  }

  allRecords(): NotificationRecord[] {
    return this.records.map(copyNotification);
  }
}

function copyNotification(
  notification: NotificationRecord,
): NotificationRecord {
  return { ...notification };
}
