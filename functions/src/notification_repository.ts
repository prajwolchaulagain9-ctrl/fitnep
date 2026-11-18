import {
  CreateNotificationResult,
  NewNotification,
  NotificationRecord,
} from "./domain";

export interface NotificationRepository {
  listForRecipient(recipientId: string): Promise<NotificationRecord[]>;

  getForRecipient(
    notificationId: string,
    recipientId: string,
  ): Promise<NotificationRecord | null>;

  markReadForRecipient(
    notificationId: string,
    recipientId: string,
  ): Promise<NotificationRecord | null>;

  markAllReadForRecipient(recipientId: string): Promise<number>;

  createIfAbsent(
    notification: NewNotification,
  ): Promise<CreateNotificationResult>;
}

export class NotificationStorageNotConfiguredError extends Error {
  constructor() {
    super("Notification storage is not configured.");
    this.name = "NotificationStorageNotConfiguredError";
  }
}

export class UnconfiguredNotificationRepository
  implements NotificationRepository
{
  private unavailable(): never {
    throw new NotificationStorageNotConfiguredError();
  }

  async listForRecipient(): Promise<NotificationRecord[]> {
    return this.unavailable();
  }

  async getForRecipient(): Promise<NotificationRecord | null> {
    return this.unavailable();
  }

  async markReadForRecipient(): Promise<NotificationRecord | null> {
    return this.unavailable();
  }

  async markAllReadForRecipient(): Promise<number> {
    return this.unavailable();
  }

  async createIfAbsent(): Promise<CreateNotificationResult> {
    return this.unavailable();
  }
}
