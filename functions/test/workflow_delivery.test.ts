import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { buildIntakeWorkflowNotification } from "../src/workflow_delivery";

describe("intake information request notification", () => {
  it("notifies the intake client that additional or clearer information is required", () => {
    const notification = buildIntakeWorkflowNotification({
      eventId: "event-1",
      eventType: "intake.information_requested",
      clientId: "client-1",
      dietitianId: "dietitian-1",
      createdAt: "2026-11-26T08:00:00.000Z",
    });

    assert(notification);
    assert.equal(notification.recipientId, "client-1");
    assert.equal(notification.referenceId, "client-1");
    assert.equal(notification.type, "intake");
    assert.equal(notification.title, "Intake information requested");
    assert.match(notification.message, /additional or clearer information/i);
  });

  it("keeps submitted intake notifications addressed to the assigned dietitian", () => {
    const notification = buildIntakeWorkflowNotification({
      eventId: "event-2",
      eventType: "intake.submitted",
      clientId: "client-1",
      dietitianId: "dietitian-1",
      createdAt: "2026-11-26T08:00:00.000Z",
    });

    assert(notification);
    assert.equal(notification.recipientId, "dietitian-1");
    assert.equal(notification.referenceId, "client-1");
  });
});
