import assert from "node:assert/strict";
import { describe, it } from "node:test";
import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  ClientIntakeError,
  ClientIntakeRecord,
  ClientIntakeRepository,
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
    const app = createFixture();

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
    });
  });

  it("denies another dietitian and client accounts", async () => {
    const app = createFixture();

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
    const app = createFixture();

    await request(app)
      .get("/dietitian/assigned-clients/client-2/intake")
      .set(bearer("dietitian-a"))
      .expect(404);
  });
});

function createFixture() {
  return createNotificationApp({
    authVerifier: new FakeAuthVerifier({
      "dietitian-a": dietitianA,
      "dietitian-b": dietitianB,
      client,
    }),
    notificationRepository: new InMemoryNotificationRepository(),
    clientIntakeService: new ClientIntakeService(new FakeClientIntakeRepository()),
  });
}

class FakeClientIntakeRepository implements ClientIntakeRepository {
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
