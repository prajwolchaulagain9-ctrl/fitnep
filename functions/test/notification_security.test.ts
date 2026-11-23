import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import { AuthenticatedUser } from "../src/domain";
import { createNotificationApp } from "../src/http_app";
import { UnconfiguredNotificationRepository } from "../src/notification_repository";
import { PrivacyPreferences, defaultSharingChoices } from "../src/privacy_preferences_repository";
import { PrivacyAcceptanceError, privacyPolicyVersion, validatePrivacyAcceptance } from "../src/privacy_policy_acceptance";
import { PrivateRecordAccessService, PrivateRecordAuthorizationError } from "../src/nutrition_record_access_service";
import {
  NotificationWorkflowService,
  WorkflowAuthorizationError,
} from "../src/notification_service";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

const clientA: AuthenticatedUser = { uid: "client-a", role: "client" };
const clientB: AuthenticatedUser = { uid: "client-b", role: "client" };
const dietitian: AuthenticatedUser = {
  uid: "dietitian-1",
  role: "dietitian",
};
const admin: AuthenticatedUser = { uid: "admin-1", role: "admin" };

describe("recipient-based notification security", () => {
  let repository: InMemoryNotificationRepository;
  let workflows: NotificationWorkflowService;
  let app: ReturnType<typeof createNotificationApp>;
  let sequence: number;

  beforeEach(() => {
    sequence = 0;
    repository = new InMemoryNotificationRepository();
    workflows = new NotificationWorkflowService(repository, {
      now: () => new Date("2026-11-18T10:00:00.000Z"),
      idFactory: () => `notification-${++sequence}`,
    });
    app = createNotificationApp({
      authVerifier: new FakeAuthVerifier({
        "token-client-a": clientA,
        "token-client-b": clientB,
        "token-dietitian": dietitian,
        "token-admin": admin,
      }),
      notificationRepository: repository,
    });
  });

  it("1. Client A receives a new diet plan notification", async () => {
    await createClientADietPlan(workflows);

    const response = await request(app)
      .get("/notifications")
      .set(bearer("token-client-a"));

    assert.equal(response.status, 200);
    assert.equal(response.body.data.notifications.length, 1);
    assert.equal(response.body.data.notifications[0].recipient_id, clientA.uid);
    assert.equal(response.body.data.notifications[0].type, "diet_plan");
    assert.equal(response.body.data.notifications[0].reference_id, "plan-a");
  });

  it("2. Client B cannot see Client A's notification", async () => {
    await createClientADietPlan(workflows);

    const response = await request(app)
      .get("/notifications")
      .set(bearer("token-client-b"));

    assert.equal(response.status, 200);
    assert.deepEqual(response.body.data.notifications, []);
  });

  it("3. Client B cannot directly access Client A's notification", async () => {
    const created = await createClientADietPlan(workflows);

    const response = await request(app)
      .get(`/notifications/${created.notification.id}`)
      .set(bearer("token-client-b"));

    assert.equal(response.status, 403);
    assert.equal(response.body.code, "permission-denied");
    assert.equal(response.body.error, "You do not have permission to access this feature.");
  });

  it("4. Client B cannot mark Client A's notification as read", async () => {
    const created = await createClientADietPlan(workflows);

    const response = await request(app)
      .patch(`/notifications/${created.notification.id}/read`)
      .set(bearer("token-client-b"));

    assert.equal(response.status, 403);
    const stored = await repository.getForRecipient(
      created.notification.id,
      clientA.uid,
    );
    assert.equal(stored?.isRead, false);
  });

  it("5. A dietitian cannot access unauthorized client notifications", async () => {
    const created = await createClientADietPlan(workflows);

    const listResponse = await request(app)
      .get("/notifications")
      .set(bearer("token-dietitian"));
    const directResponse = await request(app)
      .get(`/notifications/${created.notification.id}`)
      .set(bearer("token-dietitian"));

    assert.equal(listResponse.status, 200);
    assert.deepEqual(listResponse.body.data.notifications, []);
    assert.equal(directResponse.status, 403);
  });

  it("6. Mark All as Read updates only the authenticated recipient", async () => {
    await workflows.messageReceived({
      messageId: "message-a",
      conversationId: "conversation-a",
      recipientId: clientA.uid,
    });
    await workflows.messageReceived({
      messageId: "message-b",
      conversationId: "conversation-b",
      recipientId: clientB.uid,
    });

    const response = await request(app)
      .patch("/notifications/read-all")
      .set(bearer("token-client-a"));

    assert.equal(response.status, 200);
    assert.equal(response.body.data.updated_count, 1);
    assert.equal(
      (await repository.listForRecipient(clientA.uid))[0]?.isRead,
      true,
    );
    assert.equal(
      (await repository.listForRecipient(clientB.uid))[0]?.isRead,
      false,
    );
  });

  it("7. New messages notify the correct recipient", async () => {
    await workflows.messageReceived({
      messageId: "message-7",
      conversationId: "conversation-7",
      recipientId: clientB.uid,
      senderName: "Client A",
    });

    assert.deepEqual(await repository.listForRecipient(clientA.uid), []);
    const notifications = await repository.listForRecipient(clientB.uid);
    assert.equal(notifications.length, 1);
    assert.equal(notifications[0]?.recipientId, clientB.uid);
    assert.equal(notifications[0]?.type, "message");
    assert.equal(notifications[0]?.referenceId, "conversation-7");
  });

  it("8. New tasks notify only the assignee", async () => {
    await workflows.taskAssigned(dietitian, {
      taskId: "task-8",
      assigneeId: clientA.uid,
      taskTitle: "Record breakfast",
    });

    const notifications = await repository.listForRecipient(clientA.uid);
    assert.equal(notifications.length, 1);
    assert.equal(notifications[0]?.recipientId, clientA.uid);
    assert.equal(notifications[0]?.type, "task");
    assert.equal(notifications[0]?.referenceId, "task-8");
    assert.deepEqual(await repository.listForRecipient(clientB.uid), []);
  });

  it("9. Diet plan generation is recipient-correct and idempotent", async () => {
    const first = await createClientADietPlan(workflows);
    const retried = await createClientADietPlan(workflows);

    assert.equal(first.created, true);
    assert.equal(retried.created, false);
    assert.equal(repository.allRecords().length, 1);
    assert.throws(
      () =>
        workflows.dietPlanAssigned(clientA, {
          planId: "unauthorized-plan",
          clientId: clientA.uid,
        }),
      WorkflowAuthorizationError,
    );
  });

  it("10. Only successful payments generate recipient notifications", async () => {
    const pending = await workflows.paymentStatusChanged({
      paymentId: "payment-pending",
      recipientId: clientA.uid,
      status: "pending",
    });
    const failed = await workflows.paymentStatusChanged({
      paymentId: "payment-failed",
      recipientId: clientA.uid,
      status: "failed",
    });
    const successful = await workflows.paymentStatusChanged({
      paymentId: "payment-success",
      recipientId: clientA.uid,
      status: "succeeded",
      amountLabel: "NPR 2,500",
    });
    const retried = await workflows.paymentStatusChanged({
      paymentId: "payment-success",
      recipientId: clientA.uid,
      status: "confirmed",
      amountLabel: "NPR 2,500",
    });

    assert.equal(pending, null);
    assert.equal(failed, null);
    assert.equal(successful?.created, true);
    assert.equal(retried?.created, false);
    const notifications = await repository.listForRecipient(clientA.uid);
    assert.equal(notifications.length, 1);
    assert.equal(notifications[0]?.recipientId, clientA.uid);
    assert.equal(notifications[0]?.type, "payment");
    assert.equal(notifications[0]?.referenceId, "payment-success");
  });

  it("rejects frontend attempts to override recipient identity", async () => {
    const queryResponse = await request(app)
      .get("/notifications")
      .query({ recipient_id: clientB.uid })
      .set(bearer("token-client-a"));
    const bodyResponse = await request(app)
      .patch("/notifications/read-all")
      .send({ recipientId: clientB.uid })
      .set(bearer("token-client-a"));

    assert.equal(queryResponse.status, 400);
    assert.equal(bodyResponse.status, 400);
  });

  it("requires a valid authenticated role", async () => {
    const missingToken = await request(app).get("/notifications");
    const invalidToken = await request(app)
      .get("/notifications")
      .set(bearer("unknown-token"));

    assert.equal(missingToken.status, 401);
    assert.equal(invalidToken.status, 401);
  });

  it("does not give administrators an implicit recipient bypass", async () => {
    await createClientADietPlan(workflows);

    const response = await request(app)
      .get("/notifications")
      .set(bearer("token-admin"));

    assert.equal(response.status, 200);
    assert.deepEqual(response.body.data.notifications, []);
  });

  it("fails closed until persistent notification storage is configured", async () => {
    const unconfiguredApp = createNotificationApp({
      authVerifier: new FakeAuthVerifier({ "token-client-a": clientA }),
      notificationRepository: new UnconfiguredNotificationRepository(),
    });

    const response = await request(unconfiguredApp)
      .get("/notifications")
      .set(bearer("token-client-a"));

    assert.equal(response.status, 503);
    assert.equal(
      response.body.error,
      "Notification storage has not been configured yet.",
    );
  });
});

it("stores privacy choices for the authenticated client only", async () => {
  const stored = new Map<string, PrivacyPreferences>();
  const app = createNotificationApp({
    authVerifier: new FakeAuthVerifier({
      "token-client-a": clientA,
      "token-client-b": clientB,
      "token-dietitian": dietitian,
    }),
    notificationRepository: new InMemoryNotificationRepository(),
    privacyPreferencesRepository: {
      async getForClient(uid) {
        return stored.get(uid) ?? { ...defaultSharingChoices, updatedAt: null };
      },
      async updateSharing(uid, changes) {
        const preference = { ...await this.getForClient(uid), ...changes };
        stored.set(uid, preference);
        return preference;
      },
    },
  });
  const path = "/privacy/preferences";
  const firstClient = bearer("token-client-a");
  await request(app).get(path).expect(401);
  await request(app)
    .patch(path)
    .set(bearer("token-dietitian"))
    .send({ share_nutrition_records: true })
    .expect(403);
  await request(app)
    .patch(path)
    .set(firstClient)
    .send({ share_nutrition_records: true, share_progress_photos: true })
    .expect(200);
  const enabled = await request(app).get(path).set(firstClient).expect(200);
  assert.equal(enabled.body.data.preferences.share_nutrition_records, true);
  assert.equal(enabled.body.data.preferences.share_progress_photos, true);
  assert.equal(enabled.body.data.preferences.share_meal_photos, false);
  assert.equal(enabled.body.data.preferences.share_activity_data, false);

  const other = await request(app)
    .get(path)
    .set(bearer("token-client-b"))
    .expect(200);
  assert.equal(other.body.data.preferences.share_nutrition_records, false);

  const disabled = await request(app)
    .patch(path)
    .set(firstClient)
    .send({ share_nutrition_records: false })
    .expect(200);
  assert.equal(disabled.body.data.preferences.share_nutrition_records, false);
  assert.equal(disabled.body.data.preferences.share_progress_photos, true);
  assert.equal(stored.get(clientA.uid)?.shareNutritionRecords, false);
  await request(app).patch(path).set(firstClient).send({ share_activity_data: "true" }).expect(400);
  await request(app).patch(path).set(firstClient).send({ role: "admin" }).expect(400);
});

it("validates the current policy and guardian confirmation before registration", () => {
  const form = {
    age: 17,
    privacy_policy_version: privacyPolicyVersion,
    privacy_policy_accepted: true,
  };
  assert.throws(() => validatePrivacyAcceptance({ ...form, privacy_policy_accepted: false }), PrivacyAcceptanceError);
  assert.throws(() => validatePrivacyAcceptance({ ...form, privacy_policy_version: "old" }), PrivacyAcceptanceError);
  assert.throws(() => validatePrivacyAcceptance(form), PrivacyAcceptanceError);
  assert.deepEqual(
    validatePrivacyAcceptance({ ...form, guardian_consent_confirmed: true }),
    { age: 17, guardianConsentConfirmed: true },
  );
  assert.deepEqual(
    validatePrivacyAcceptance({ ...form, age: 18 }),
    { age: 18, guardianConsentConfirmed: false },
  );
});

it("withdrawing optional consent blocks collection and dietitian access while preserving owner access", async () => {
  let assignedDietitian = dietitian.uid;
  let shareActivityData = false;
  const access = new PrivateRecordAccessService({
    async getCurrentTeam() { return { dietitianId: assignedDietitian, teamMemberIds: [] }; },
  }, {
    async getForClient() { return { ...defaultSharingChoices, shareActivityData, updatedAt: null }; },
  }, {
    async hasCurrentAcceptance() { return true; },
  });
  const choice = "shareActivityData";
  await assert.rejects(access.assertCanCollect(clientA, clientA.uid, choice), PrivateRecordAuthorizationError);
  shareActivityData = true;
  await access.assertCanCollect(clientA, clientA.uid, choice);
  await access.assertCanRead(dietitian, clientA.uid, choice);
  await assert.rejects(access.assertCanRead(admin, clientA.uid, choice), PrivateRecordAuthorizationError);
  await assert.rejects(access.assertCanRead(clientB, clientA.uid, choice), PrivateRecordAuthorizationError);
  assignedDietitian = "replacement";
  await assert.rejects(access.assertCanRead(dietitian, clientA.uid, choice), PrivateRecordAuthorizationError);
  assignedDietitian = dietitian.uid;
  shareActivityData = false;
  await assert.rejects(access.assertCanRead(dietitian, clientA.uid, choice), PrivateRecordAuthorizationError);
  await assert.rejects(access.assertCanCollect(clientA, clientA.uid, choice), PrivateRecordAuthorizationError);
  await access.assertCanRead(clientA, clientA.uid, choice);
});

class FakeAuthVerifier implements AuthVerifier {
  constructor(private readonly usersByToken: Record<string, AuthenticatedUser>) {}

  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    const user = this.usersByToken[token];
    if (user === undefined) {
      throw new AuthenticationError("The authentication token is invalid.");
    }
    return user;
  }
}

function bearer(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` };
}

function createClientADietPlan(workflows: NotificationWorkflowService) {
  return workflows.dietPlanAssigned(dietitian, {
    planId: "plan-a",
    clientId: clientA.uid,
    planTitle: "Client A weekly plan",
  });
}
