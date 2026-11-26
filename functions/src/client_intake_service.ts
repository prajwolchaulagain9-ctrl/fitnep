import {
  IntakeAnswerError,
  IntakeAnswers,
  isObject,
  parseIntakeAnswers,
  validateIntakeMeasurements,
} from "./client_intake_answers";
import { AuthenticatedUser } from "./domain";

export const clientIntakeReviewActions = [
  "reviewed",
  "missing_information",
  "clarification_requested",
] as const;

export type ClientIntakeReviewAction =
  (typeof clientIntakeReviewActions)[number];
export type ClientIntakeStatus =
  "submitted" | "reviewed" | "information_requested";

export interface ClientIntakeReview {
  action: ClientIntakeReviewAction | null;
  note: string | null;
  updatedAt: string | null;
}

export interface ClientIntakeReviewUpdate {
  expectedVersion?: number;
  action: ClientIntakeReviewAction;
  note: string | null;
  status: ClientIntakeStatus;
}

export interface ClientIntakeReviewContext {
  actor: AuthenticatedUser;
  correlationId: string;
}

export interface ClientIntakeField {
  label: string;
  value: string;
}

export interface ClientIntakeSection {
  title: string;
  fields: ClientIntakeField[];
}

export interface ClientIntakeRecord {
  version?: number;
  clientId: string;
  allergies: string[];
  medicalConditions: string[];
  sections: ClientIntakeSection[];
  submittedAt: string | null;
  updatedAt: string | null;
  status: ClientIntakeStatus;
  review: ClientIntakeReview;
}

export interface IntakeWorkspace {
  clientId: string;
  answers: IntakeAnswers;
  draftRevision: number;
  version: number;
  latest: ClientIntakeRecord | null;
  membershipActive: boolean;
  guardianConfirmed: boolean;
}

export interface IntakeDraftWrite {
  answers: IntakeAnswers;
  expectedVersion: number;
  expectedDraftRevision: number;
  guardianConfirmed: boolean;
}

export interface ClientIntakeRepository {
  getForAssignedDietitian(
    clientId: string,
    dietitianId: string,
    context?: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord>;
  getForOwner?(actor: AuthenticatedUser, correlationId: string): Promise<ClientIntakeRecord>;
  getWorkspace?(actor: AuthenticatedUser, correlationId: string): Promise<IntakeWorkspace>;
  saveDraft?(actor: AuthenticatedUser, input: IntakeDraftWrite, correlationId: string): Promise<IntakeWorkspace>;
  updateReviewForAssignedDietitian(
    clientId: string,
    dietitianId: string,
    review: ClientIntakeReviewUpdate,
    context: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord>;
}

export class ClientIntakeError extends Error {
  constructor(
    readonly statusCode: 400 | 403 | 404 | 409 | 503,
    message: string,
  ) {
    super(message);
    this.name = "ClientIntakeError";
  }
}

export class ClientIntakeService {
  constructor(private readonly repository: ClientIntakeRepository) {}

  async getAssignedClientIntake(
    actor: AuthenticatedUser,
    clientIdInput: unknown,
    correlationId = "intake-read",
  ): Promise<ClientIntakeRecord> {
    if (actor.role !== "dietitian") {
      throw new ClientIntakeError(
        403,
        "Dietitian access is required to view client intake forms.",
      );
    }
    const clientId = requiredIdentifier(clientIdInput);
    return this.repository.getForAssignedDietitian(clientId, actor.uid, { actor, correlationId });
  }

  async getOwnIntake(actor: AuthenticatedUser, correlationId: string) {
    if (actor.role !== "client") throw new ClientIntakeError(403, "Client access is required.");
    if (!this.repository.getForOwner) throw new ClientIntakeError(503, "Intake storage is unavailable.");
    return this.repository.getForOwner(actor, correlationId);
  }

  async getOwnWorkspace(actor: AuthenticatedUser, correlationId: string): Promise<IntakeWorkspace> {
    requireVerifiedClient(actor);
    if (!this.repository.getWorkspace) {
      throw new ClientIntakeError(503, "Intake storage is unavailable.");
    }
    return this.repository.getWorkspace(actor, correlationId);
  }

  async saveOwnDraft(actor: AuthenticatedUser, input: unknown, correlationId: string): Promise<IntakeWorkspace> {
    requireVerifiedClient(actor);
    if (!this.repository.saveDraft) {
      throw new ClientIntakeError(503, "Intake storage is unavailable.");
    }
    return this.repository.saveDraft(actor, parseDraftWrite(input, actor.uid), correlationId);
  }

  async updateAssignedClientIntakeReview(
    actor: AuthenticatedUser,
    clientIdInput: unknown,
    input: unknown,
    correlationId: string,
  ): Promise<ClientIntakeRecord> {
    if (actor.role !== "dietitian") {
      throw new ClientIntakeError(
        403,
        "Dietitian access is required to review client intake forms.",
      );
    }
    const clientId = requiredIdentifier(clientIdInput);
    const review = reviewUpdate(input);
    return this.repository.updateReviewForAssignedDietitian(
      clientId,
      actor.uid,
      review,
      { actor, correlationId },
    );
  }
}

function reviewUpdate(value: unknown): ClientIntakeReviewUpdate {
  if (!isObject(value) ||
      Object.keys(value).some(key => !["action", "note", "expected_version"].includes(key)) ||
      (value.expected_version !== undefined && (!Number.isSafeInteger(value.expected_version) || (value.expected_version as number) < 1)) ||
      typeof value.action !== "string" ||
      !clientIntakeReviewActions.includes(value.action as ClientIntakeReviewAction)) {
    throw new ClientIntakeError(400, "A valid intake review action is required.");
  }
  const action = value.action as ClientIntakeReviewAction;
  if (action === "reviewed") {
    if (value.note !== undefined && value.note !== null && value.note !== "") {
      throw new ClientIntakeError(
        400,
        "A note is only used when requesting information.",
      );
    }
    return { action, note: null, status: "reviewed", expectedVersion: value.expected_version as number | undefined };
  }
  if (typeof value.note !== "string" ||
      !value.note.trim() || value.note.trim().length > 1000) {
    throw new ClientIntakeError(
      400,
      "Describe the missing or unclear information in 1000 characters or less.",
    );
  }
  return {
    action,
    note: value.note.trim(),
    status: "information_requested",
    expectedVersion: value.expected_version as number | undefined,
  };
}

function requiredIdentifier(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) {
    throw new ClientIntakeError(400, "Client id is invalid.");
  }
  return value;
}

function requireVerifiedClient(actor: AuthenticatedUser): void {
  if (actor.role !== "client" || actor.emailVerified !== true) {
    throw new ClientIntakeError(403, "A verified client account is required.");
  }
}

function parseDraftWrite(value: unknown, uid: string): IntakeDraftWrite {
  const fields = [
    "answers", "expected_client_id", "expected_version", "expected_draft_revision",
    "guardian_consent_confirmed",
  ];
  if (!isObject(value) || Object.keys(value).some(key => !fields.includes(key)) ||
      typeof value.expected_client_id !== "string" ||
      !isRevision(value.expected_version) || !isRevision(value.expected_draft_revision) ||
      typeof value.guardian_consent_confirmed !== "boolean") {
    throw new ClientIntakeError(400, "Supply the current intake version, draft revision and form answers.");
  }
  if (value.expected_client_id !== uid) {
    throw new ClientIntakeError(403, "The signed-in account changed. Reopen the intake form.");
  }
  try {
    const answers = parseIntakeAnswers(value.answers);
    validateIntakeMeasurements(answers);
    return {
      answers,
      expectedVersion: value.expected_version,
      expectedDraftRevision: value.expected_draft_revision,
      guardianConfirmed: value.guardian_consent_confirmed,
    };
  } catch (error) {
    if (error instanceof IntakeAnswerError) throw new ClientIntakeError(400, error.message);
    throw error;
  }
}

function isRevision(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
}
