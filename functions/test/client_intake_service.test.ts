import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  ClientIntakeRecord,
  ClientIntakeRepository,
  ClientIntakeReviewContext,
  ClientIntakeReviewUpdate,
  ClientIntakeService,
} from "../src/client_intake_service";
import { AuthenticatedUser } from "../src/domain";

const dietitian: AuthenticatedUser = {
  uid: "dietitian-1",
  role: "dietitian",
};

describe("client intake review service", () => {
  it("saves reviewed as the intake status", async () => {
    const repository = new FakeClientIntakeRepository();
    const service = new ClientIntakeService(repository);

    const intake = await service.updateAssignedClientIntakeReview(
      dietitian,
      "client-1",
      { action: "reviewed" },
      "request-reviewed",
    );

    assert.equal(repository.saved?.action, "reviewed");
    assert.equal(repository.saved?.status, "reviewed");
    assert.equal(intake.status, "reviewed");
  });

  it("saves missing information as information requested", async () => {
    const repository = new FakeClientIntakeRepository();
    const service = new ClientIntakeService(repository);

    const intake = await service.updateAssignedClientIntakeReview(
      dietitian,
      "client-1",
      {
        action: "missing_information",
        note: " Please provide the current medication dosage. ",
      },
      "request-missing",
    );

    assert.equal(repository.saved?.action, "missing_information");
    assert.equal(repository.saved?.status, "information_requested");
    assert.equal(
      repository.saved?.note,
      "Please provide the current medication dosage.",
    );
    assert.equal(intake.status, "information_requested");
  });

  it("saves clarification as information requested", async () => {
    const repository = new FakeClientIntakeRepository();
    const service = new ClientIntakeService(repository);

    await service.updateAssignedClientIntakeReview(
      dietitian,
      "client-1",
      {
        action: "clarification_requested",
        note: "Please clarify the allergy reaction.",
      },
      "request-clarification",
    );

    assert.equal(repository.saved?.action, "clarification_requested");
    assert.equal(repository.saved?.status, "information_requested");
  });
});

class FakeClientIntakeRepository implements ClientIntakeRepository {
  saved: ClientIntakeReviewUpdate | null = null;

  async getForAssignedDietitian(): Promise<ClientIntakeRecord> {
    return this.record();
  }

  async updateReviewForAssignedDietitian(
    _clientId: string,
    _dietitianId: string,
    review: ClientIntakeReviewUpdate,
    _context: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord> {
    this.saved = review;
    return this.record();
  }

  private record(): ClientIntakeRecord {
    return {
      clientId: "client-1",
      allergies: [],
      medicalConditions: [],
      sections: [],
      submittedAt: "2026-11-20T08:00:00.000Z",
      updatedAt: null,
      status: this.saved?.status ?? "submitted",
      review: {
        action: this.saved?.action ?? null,
        note: this.saved?.note ?? null,
        updatedAt: this.saved === null ? null : "2026-11-25T10:00:00.000Z",
      },
    };
  }
}
