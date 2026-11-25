import assert from "node:assert/strict";
import { describe, it } from "node:test";
import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  ClientIntakeError,
  ClientIntakeRecord,
  ClientIntakeRepository,
  ClientIntakeReviewContext,
  ClientIntakeReviewUpdate,
  ClientIntakeService,
} from "../src/client_intake_service";
import { AuthenticatedUser } from "../src/domain";
import { createNotificationApp } from "../src/http_app";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

const dietitianA: AuthenticatedUser = {
  uid: "dietitian-a",
  role: "dietitian",
};
const dietitianB: AuthenticatedUser = {
  uid: "dietitian-b",
  role: "dietitian",
};
const client: AuthenticatedUser = { uid: "client-1", role: "client" };

describe("assigned client intake API", () => {
  it("returns the complete saved intake to the assigned dietitian", async () => {
    const { app } = createFixture();

    const response = await request(app)
      .get("/dietitian/assigned-clients/client-1/intake")
      .set(bearer("dietitian-a"))
      .expect(200);

    assert.deepEqual(response.body.data.intake, {
      client_id: "client-1",
      allergies: ["Peanuts", "Shellfish"],
      medical_conditions: ["Type 2 diabetes"],
      sections: [
        {
          title: "Health information",
          fields: [
            { label: "Height", value: "168 cm" },
            { label: "Weight", value: "72 kg" },
          ],
        },
        {
          title: "Goals",
          fields: [{ label: "Primary goal", value: "Improve glucose control" }],
        },
        {
          title: "Restrictions",
          fields: [{ label: "Dietary", value: "Vegetarian" }],
        },
        {
          title: "Additional information",
          fields: [{ label: "Sleep", value: "7 hours" }],
        },
      ],
      submitted_at: "2026-11-20T08:00:00.000Z",
      updated_at: "2026-11-22T09:30:00.000Z",
      status: "submitted",
      review_action: null,
      review_note: null,
      review_updated_at: null,
    });
  });

  it("marks the intake as reviewed and saves the selected action", async () => {
    const { app, repository } = createFixture();

    const response = await request(app)
      .patch("/dietitian/assigned-clients/client-1/intake/review")
      .set(bearer("dietitian-a"))
      .send({ action: "reviewed" })
      .expect(200);

    assert.equal(repository.savedReview?.action, "reviewed");
    assert.equal(repository.savedReview?.status, "reviewed");
    assert.equal(repository.savedReview?.note, null);
    assert.equal(response.body.data.intake.status, "reviewed");
    assert.equal(response.body.data.intake.review_action, "reviewed");
  });

  it("requests missing information and saves the request note", async () => {
    const { app, repository } = createFixture();

    const response = await request(app)
      .patch("/dietitian/assigned-clients/client-1/intake/review")
      .set(bearer("dietitian-a"))
      .send({
        action: "missing_information",
        note: "Please provide the current medication dosage.",
      })
      .expect(200);

    assert.equal(repository.savedReview?.action, "missing_information");
    assert.equal(repository.savedReview?.status, "information_requested");
    assert.equal(
      repository.savedReview?.note,
      "Please provide the current medication dosage.",
    );
    assert.equal(response.body.data.intake.status, "information_requested");
    assert.equal(response.body.data.intake.review_action, "missing_information");
  });

  it("requests clarification when submitted information is unclear", async () => {
    const { app, repository } = createFixture();

    await request(app)
      .patch("/dietitian/assigned-clients/client-1/intake/review")
      .set(bearer("dietitian-a"))
      .send({
        action: "clarification_requested",
        note: "Please clarify whether the allergy causes anaphylaxis.",
      })
      .expect(200);

    assert.equal(repository.savedReview?.action, "clarification_requested");
    assert.equal(repository.savedReview?.status, "information_requested");
  });

  it("denies another dietitian and client accounts", async () => {
    const { app } = createFixture();

    await request(app)
      .get("/dietitian/assigned-clients/client-1/intake")
      .set(bearer("dietitian-b"))
      .expect(403);
    await request(app)
      .get("/dietitian/assigned-clients/client-1/intake")
      .set(bearer("client"))
      .expect(403);
  });

  it("returns not found when the assigned client has no saved intake", async () => {
    const { app } = createFixture();

    await request(app)
      .get("/dietitian/assigned-clients/client-2/intake")
      .set(bearer("dietitian-a"))
      .expect(404);
  });
});

function createFixture() {
  const repository = new FakeClientIntakeRepository();
  const app = createNotificationApp({
    authVerifier: new FakeAuthVerifier({
      "dietitian-a": dietitianA,
      "dietitian-b": dietitianB,
      client,
    }),
    notificationRepository: new InMemoryNotificationRepository(),
    clientIntakeService: new ClientIntakeService(repository),
  });
  return { app, repository };
}

class FakeClientIntakeRepository implements ClientIntakeRepository {
  savedReview: ClientIntakeReviewUpdate | null = null;

  async getForAssignedDietitian(
    clientId: string,
    dietitianId: string,
  ): Promise<ClientIntakeRecord> {
    if (dietitianId !== "dietitian-a") {
      throw new ClientIntakeError(403, "This client is not currently assigned to you.");
    }
    if (clientId !== "client-1") {
      throw new ClientIntakeError(404, "Client intake form not found.");
    }
    return this.record(clientId);
  }

  async updateReviewForAssignedDietitian(
    clientId: string,
    dietitianId: string,
    review: ClientIntakeReviewUpdate,
    _context: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord> {
    if (dietitianId !== "dietitian-a") {
      throw new ClientIntakeError(403, "This client is not currently assigned to you.");
    }
    if (clientId !== "client-1") {
      throw new ClientIntakeError(404, "Client intake form not found.");
    }
    this.savedReview = review;
    return this.record(clientId);
  }

  private record(clientId: string): ClientIntakeRecord {
    return {
      clientId,
      allergies: ["Peanuts", "Shellfish"],
      medicalConditions: ["Type 2 diabetes"],
      sections: [
        {
          title: "Health information",
          fields: [
            { label: "Height", value: "168 cm" },
            { label: "Weight", value: "72 kg" },
          ],
        },
        {
          title: "Goals",
          fields: [{ label: "Primary goal", value: "Improve glucose control" }],
        },
        {
          title: "Restrictions",
          fields: [{ label: "Dietary", value: "Vegetarian" }],
        },
        {
          title: "Additional information",
          fields: [{ label: "Sleep", value: "7 hours" }],
        },
      ],
      submittedAt: "2026-11-20T08:00:00.000Z",
      updatedAt: "2026-11-22T09:30:00.000Z",
      status: this.savedReview?.status ?? "submitted",
      review: {
        action: this.savedReview?.action ?? null,
        note: this.savedReview?.note ?? null,
        updatedAt: this.savedReview === null
          ? null
          : "2026-11-25T10:00:00.000Z",
      },
    };
  }
}

class FakeAuthVerifier implements AuthVerifier {
  constructor(private readonly users: Record<string, AuthenticatedUser>) {}

  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    const user = this.users[token];
    if (!user) throw new AuthenticationError("Invalid token.");
    return user;
  }
}

function bearer(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` };
}
