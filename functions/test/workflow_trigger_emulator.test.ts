import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Firestore, getFirestore } from "firebase-admin/firestore";

import { NotificationRecord } from "../src/domain";
import { FirestoreNotificationRepository } from "../src/firestore_notification_repository";

const projectId = "demo-fitnep";
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const runTriggerTests = process.env.FITNEP_RUN_TRIGGER_TESTS === "true";
const emulatorDescribe =
  emulatorHost === undefined || !runTriggerTests ? describe.skip : describe;

emulatorDescribe("Firestore notification workflow triggers", () => {
  let app: App;
  let firestore: Firestore;
  let repository: FirestoreNotificationRepository;

  before(() => {
    app = initializeApp({ projectId }, "workflow-trigger-tests");
    firestore = getFirestore(app);
    repository = new FirestoreNotificationRepository(firestore);
  });

  beforeEach(clearFirestore);

  after(async () => {
    await deleteApp(app);
  });

  it(
    "creates recipient-correct, idempotent notifications for all workflows",
    { timeout: 30_000 },
    async () => {
      await firestore.collection("diet_plans").doc("plan-trigger").create({
        client_id: "client-a",
        assigned_by_id: "dietitian-1",
        assigned_by_role: "dietitian",
        title: "Trigger diet plan",
      });
      await firestore.collection("messages").doc("message-trigger").create({
        conversation_id: "conversation-trigger",
        recipient_id: "client-b",
        sender_name: "Client A",
      });
      await firestore.collection("tasks").doc("task-trigger").create({
        assignee_id: "client-a",
        assigned_by_id: "dietitian-1",
        assigned_by_role: "dietitian",
        title: "Trigger task",
      });

      const payment = firestore.collection("payments").doc("payment-trigger");
      await payment.create({
        recipient_id: "client-a",
        status: "pending",
        amount_label: "NPR 2,500",
      });
      await payment.update({ status: "succeeded" });

      const [clientA, clientB] = await Promise.all([
        waitForNotifications(repository, "client-a", 3),
        waitForNotifications(repository, "client-b", 1),
      ]);

      assert.deepEqual(notificationKeys(clientA), [
        "diet_plan:plan-trigger",
        "payment:payment-trigger",
        "task:task-trigger",
      ]);
      assert.deepEqual(notificationKeys(clientB), [
        "message:conversation-trigger",
      ]);

      await payment.update({ status: "confirmed" });
      await waitForSettledTriggers();

      assert.equal(
        (await repository.listForRecipient("client-a")).length,
        3,
      );
      assert.equal(
        (await repository.listForRecipient("client-b")).length,
        1,
      );
    },
  );

  it(
    "does not notify for pending or failed payments",
    { timeout: 20_000 },
    async () => {
      const payment = firestore.collection("payments").doc("payment-failed");
      await payment.create({
        recipient_id: "client-a",
        status: "pending",
      });
      await payment.update({ status: "failed" });
      await waitForSettledTriggers();

      assert.deepEqual(await repository.listForRecipient("client-a"), []);
    },
  );
});

function notificationKeys(notifications: NotificationRecord[]): string[] {
  return notifications
    .map((notification) => `${notification.type}:${notification.referenceId}`)
    .sort();
}

async function waitForNotifications(
  repository: FirestoreNotificationRepository,
  recipientId: string,
  expectedCount: number,
): Promise<NotificationRecord[]> {
  const deadline = Date.now() + 20_000;
  let notifications: NotificationRecord[] = [];

  while (Date.now() < deadline) {
    notifications = await repository.listForRecipient(recipientId);
    if (notifications.length === expectedCount) return notifications;
    await delay(250);
  }

  throw new Error(
    `Expected ${expectedCount} notifications for ${recipientId}, found ${notifications.length}.`,
  );
}

function waitForSettledTriggers(): Promise<void> {
  return delay(1_500);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function clearFirestore(): Promise<void> {
  const response = await fetch(
    `http://${emulatorHost}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!response.ok) {
    throw new Error(`Could not clear Firestore emulator: ${response.status}`);
  }
}
