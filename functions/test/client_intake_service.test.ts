import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { ageRequiresGuardian, intakeAge, parseIntakeAnswers, validateIntakeSubmission } from "../src/client_intake_answers";
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

describe("US 12 client intake answers", () => {
  const today = new Date("2026-11-26T12:00:00Z");
  const answers = {
    full_name: "Test Client", age: "16", date_of_birth: "2010-11-26",
    contact_email: "client@example.test", height_cm: "175", weight_kg: "70",
    fitness_goals: "Build endurance", medical_history: "None",
    allergies: "None", dietary_restrictions: "None", food_preferences: "Rice",
  };

  it("supports a partial draft and accepts an explicit None on submission", () => {
    assert.deepEqual(parseIntakeAnswers({ allergies: "  None  ", full_name: "   " }),
      { allergies: "None" });
    assert.equal(validateIntakeSubmission(parseIntakeAnswers(answers), today), 22.9);
    assert.throws(() => validateIntakeSubmission({ ...answers, allergies: "" }, today), /allergies is required/i);
  });

  it("uses both age and birth date to determine guardian eligibility", () => {
    assert.equal(ageRequiresGuardian({ age: "17" }, today), true);
    assert.equal(ageRequiresGuardian({ age: "18", date_of_birth: "2008-11-27" }, today), true);
    assert.equal(ageRequiresGuardian({ age: "18", date_of_birth: "2008-11-26" }, today), false);
    assert.throws(() => validateIntakeSubmission({ ...answers, age: "18" }, today), /match the date of birth/);
    assert.throws(() => intakeAge("2010-02-29", today), /valid date of birth/);
  });

  it("rejects invalid measurements and fields controlled by the server", () => {
    assert.throws(() => validateIntakeSubmission({ ...answers, height_cm: "301" }, today), /Height/);
    assert.throws(() => validateIntakeSubmission({ ...answers, waist_cm: "0" }, today), /Waist/);
    assert.throws(() => validateIntakeSubmission({ ...answers, contact_email: undefined }, today), /email or phone/);
    assert.throws(() => parseIntakeAnswers({ ...answers, bmi: "2.5", client_id: "another-client" }), /only the intake/);
  });
});

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
