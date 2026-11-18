import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";

import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";
import { NotificationWorkflowService } from "../src/notification_service";

const projectId = "demo-fitnep";
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const emulatorDescribe = emulatorHost === undefined ? describe.skip : describe;

emulatorDescribe("Firestore notification repository", () => {
  let app: App;
  let firestore: Firestore;
  let repository: FirestoreNotificationRepository;
  let workflows: NotificationWorkflowService;
  let sequence = 0;

  before(() => {
    app = initializeApp({ projectId }, "firestore-notification-tests");
    firestore = getFirestore(app);
    repository = new FirestoreNotificationRepository(firestore);
    workflows = new NotificationWorkflowService(repository, {
      now: () => new Date("2026-11-18T10:00:00.000Z"),
      idFactory: () => `ignored-${++sequence}`,
    });
  });

  beforeEach(async () => {
    sequence = 0;
    await clearFirestore();
  });

  after(async () => {
    await deleteApp(app);
  });

  it("persists recipient-scoped records and enforces idempotency", async () => {
    const first = await workflows.messageReceived({
      messageId: "message-1",
      conversationId: "conversation-1",
      recipientId: "client-a",
    });
    const retry = await workflows.messageReceived({
      messageId: "message-1",
      conversationId: "conversation-1",
      recipientId: "client-a",
    });

    assert.equal(first.created, true);
    assert.equal(retry.created, false);
    assert.equal(first.notification.id, retry.notification.id);
    assert.equal((await repository.listForRecipient("client-a")).length, 1);
    assert.deepEqual(await repository.listForRecipient("client-b"), []);

    const stored = await firestore
      .collection("notifications")
      .doc(first.notification.id)
      .get();
    assert.equal(stored.get("recipient_id"), "client-a");
    assert.equal(stored.get("reference_id"), "conversation-1");
    assert.equal(stored.get("is_read"), false);
    assert.equal(stored.get("recipientId"), undefined);
  });

  it("prevents direct reads and updates by a different recipient", async () => {
    const created = await workflows.messageReceived({
      messageId: "message-2",
      conversationId: "conversation-2",
      recipientId: "client-a",
    });

    assert.equal(
      await repository.getForRecipient(created.notification.id, "client-b"),
      null,
    );
    assert.equal(
      await repository.markReadForRecipient(
        created.notification.id,
        "client-b",
      ),
      null,
    );
    assert.equal(
      (
        await repository.getForRecipient(
          created.notification.id,
          "client-a",
        )
      )?.isRead,
      false,
    );
  });

  it("marks all unread records for only one recipient", async () => {
    await workflows.messageReceived({
      messageId: "message-a-1",
      conversationId: "conversation-a",
      recipientId: "client-a",
    });
    await workflows.taskAssigned(
      { uid: "dietitian-1", role: "dietitian" },
      { taskId: "task-a", assigneeId: "client-a" },
    );
    await workflows.messageReceived({
      messageId: "message-b-1",
      conversationId: "conversation-b",
      recipientId: "client-b",
    });

    const updatedCount = await repository.markAllReadForRecipient("client-a");

    assert.equal(updatedCount, 2);
    assert.equal(
      (await repository.listForRecipient("client-a")).every(
        (notification) => notification.isRead,
      ),
      true,
    );
    assert.equal(
      (await repository.listForRecipient("client-b"))[0]?.isRead,
      false,
    );
  });
});

async function clearFirestore(): Promise<void> {
  const response = await fetch(
    `http://${emulatorHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Could not clear Firestore emulator: ${response.status}`);
  }
}
