import {
  DocumentData,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import { AuditWriter, FirestoreAuditWriter } from "./audit";
import { ageRequiresGuardian, IntakeAnswerError, parseIntakeAnswers } from "./client_intake_answers";
import { AuthenticatedUser } from "./domain";
import { FirestorePrivateRecordsStore } from "./firestore_private_records_store";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { FirestorePackageService } from "./package_membership_service";
import { hasValidPrivacyAcceptance } from "./privacy_policy_acceptance";
import { createHash } from "node:crypto";

import {
  ClientIntakeError,
  ClientIntakeField,
  ClientIntakeRecord,
  ClientIntakeRepository,
  ClientIntakeReviewAction,
  ClientIntakeReviewContext,
  ClientIntakeReviewUpdate,
  ClientIntakeSection,
  ClientIntakeStatus,
  IntakeDraftWrite,
  IntakeWorkspace,
} from "./client_intake_service";

const reservedKeys = new Set([
  "client_id",
  "allergies",
  "food_allergies",
  "medical_conditions",
  "health_conditions",
  "health_information",
  "goals",
  "restrictions",
  "dietary_restrictions",
  "responses",
  "submitted_at",
  "updated_at",
  "status",
  "review_action",
  "review_note",
  "review_updated_at",
  "reviewed_by_id",
  "version",
  "review_revision",
]);

export class FirestoreClientIntakeRepository implements ClientIntakeRepository {
  constructor(
    private readonly firestore: Firestore,
    private readonly audit: Pick<AuditWriter, "appendInTransaction" | "appendWithEvent"> =
      new FirestoreAuditWriter(firestore),
    private readonly reads: Pick<FirestorePrivateRecordsStore, "readResource"> =
      new FirestorePrivateRecordsStore(firestore, new FirestorePrivacyPreferencesRepository(firestore), audit),
    private readonly membership: Pick<FirestorePackageService, "assignmentStatus"> =
      new FirestorePackageService(firestore),
  ) {}

  getForAssignedDietitian(
    clientId: string,
    dietitianId: string,
    context?: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord> {
    return this.readFor(context?.actor ?? { uid: dietitianId, role: "dietitian" }, clientId, context?.correlationId);
  }

  getForOwner(actor: AuthenticatedUser, correlationId: string) {
    return this.readFor(actor, actor.uid, correlationId);
  }

  getWorkspace(actor: AuthenticatedUser, correlationId: string): Promise<IntakeWorkspace> {
    return this.reads.readResource(actor, {
      clientId: actor.uid, category: "intakes", recordId: "draft", ownerOnly: true,
    }, async transaction => {
      const { workspace } = await this.loadWorkspace(transaction, actor);
      return { data: workspace };
    }, correlationId);
  }

  saveDraft(actor: AuthenticatedUser, input: IntakeDraftWrite, correlationId: string): Promise<IntakeWorkspace> {
    return this.reads.readResource(actor, {
      clientId: actor.uid, category: "intakes", recordId: "draft", ownerOnly: true,
    }, async transaction => {
      const { workspace, draft, acceptance } = await this.loadWorkspace(transaction, actor);
      if (workspace.version !== input.expectedVersion) {
        throw new ClientIntakeError(409, "Your intake changed. Reload the saved form before trying again.");
      }
      // A response can be lost after the transaction commits. Return the
      // saved answers only when they match the very next draft revision.
      if (draft.exists && workspace.draftRevision === input.expectedDraftRevision + 1 &&
          JSON.stringify(workspace.answers) === JSON.stringify(input.answers)) {
        return { data: workspace };
      }
      if (workspace.draftRevision !== input.expectedDraftRevision) {
        throw new ClientIntakeError(409, "Your intake changed. Reload the saved form before trying again.");
      }
      if (!workspace.membershipActive) {
        throw new ClientIntakeError(409, "An active membership is required to update the intake form.");
      }
      const guardianConfirmed = this.confirmGuardian(transaction, actor, acceptance, input, correlationId);
      const revision = workspace.draftRevision + 1;
      transaction.set(draft.ref, {
        client_id: actor.uid,
        revision,
        answers: input.answers,
        updated_at: FieldValue.serverTimestamp(),
      });
      return { data: {
        ...workspace, answers: input.answers, draftRevision: revision, guardianConfirmed,
      } };
    }, correlationId);
  }

  private async loadWorkspace(transaction: Transaction, actor: AuthenticatedUser) {
    const acceptance = await transaction.get(this.firestore.doc(`privacy_acceptances/${actor.uid}`));
    if (!hasValidPrivacyAcceptance(acceptance.data())) {
      throw new ClientIntakeError(403, "A current privacy acceptance is required to open intake.");
    }
    const intakeRef = this.firestore.doc(`client_intakes/${actor.uid}`);
    const [intake, draft, membership] = await Promise.all([
      transaction.get(intakeRef),
      transaction.get(intakeRef.collection("private").doc("draft")),
      this.membership.assignmentStatus(actor.uid, transaction),
    ]);
    if ((draft.exists && draft.get("client_id") !== actor.uid) ||
        (intake.get("client_id") !== undefined && intake.get("client_id") !== actor.uid)) {
      throw invalidIntake();
    }
    const latest = !intake.exists || intake.get("status") === "draft"
      ? null : parseIntake(actor.uid, intake.data());
    const revision = draft.exists ? draft.get("revision") : 0;
    if (!Number.isSafeInteger(revision) || revision < 0 || (draft.exists && draft.get("answers") === undefined)) {
      throw invalidIntake();
    }
    const savedAnswers = draft.exists ? draft.get("answers") : intake.get("answers");
    const displayName = actor.displayName?.trim();
    const email = actor.email?.trim();
    const workspace: IntakeWorkspace = {
      clientId: actor.uid,
      latest,
      version: latest?.version ?? 0,
      draftRevision: revision,
      answers: savedAnswers === undefined
        ? {
          ...(displayName && displayName !== email ? { full_name: displayName.slice(0, 160) } : {}),
          ...(email ? { contact_email: email.slice(0, 254) } : {}),
        }
        : parseSavedAnswers(savedAnswers),
      membershipActive: membership === "active",
      guardianConfirmed: acceptance.get("guardian_consent_confirmed") === true,
    };
    return { workspace, draft, acceptance };
  }

  private confirmGuardian(
    transaction: Transaction,
    actor: AuthenticatedUser,
    acceptance: DocumentSnapshot,
    input: IntakeDraftWrite,
    correlationId: string,
  ): boolean {
    const existing = acceptance.get("guardian_consent_confirmed") === true;
    let minor: boolean;
    try {
      minor = ageRequiresGuardian(input.answers, new Date());
    } catch (error) {
      if (error instanceof IntakeAnswerError) throw new ClientIntakeError(400, error.message);
      throw error;
    }
    if (!minor || existing) return existing;
    if (!input.guardianConfirmed) {
      throw new ClientIntakeError(400, "Confirm permission from a parent or guardian before saving.");
    }
    transaction.update(acceptance.ref, {
      guardian_consent_confirmed: true,
      guardian_consent_confirmed_at: FieldValue.serverTimestamp(),
    });
    this.audit.appendInTransaction(transaction, {
      actor, action: "privacy.accepted", targetType: "account", targetId: actor.uid,
      clientId: actor.uid, status: "guardian_confirmed", outcome: "succeeded", correlationId,
    });
    return true;
  }

  private readFor(actor: AuthenticatedUser, clientId: string, correlationId?: string) {
    return this.reads.readResource(actor, { clientId, category: "intakes", recordId: "submitted" }, async transaction => {
      const intake = await transaction.get(this.firestore.doc(`client_intakes/${clientId}`));
      if (!intake.exists) {
        throw new ClientIntakeError(404, "Client intake form not found.");
      }
      if (intake.get("status") === "draft") throw new ClientIntakeError(404, "No submitted intake form exists.");
      return { data: parseIntake(clientId, intake.data()) };
    }, correlationId);
  }

  updateReviewForAssignedDietitian(
    clientId: string,
    dietitianId: string,
    review: ClientIntakeReviewUpdate,
    context: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord> {
    return this.reads.readResource(context.actor, { clientId, category: "intakes", recordId: "submitted" }, async transaction => {
      const assignmentReference = this.firestore
        .collection("client_assignments")
        .doc(clientId);
      const intakeReference = this.firestore
        .collection("client_intakes")
        .doc(clientId);
      const [assignment, intake] = await Promise.all([
        transaction.get(assignmentReference),
        transaction.get(intakeReference),
      ]);
      requireAssignment(assignment, dietitianId);
      if (!intake.exists) {
        throw new ClientIntakeError(404, "Client intake form not found.");
      }
      const version = intake.get("version") ?? 1;
      if (!Number.isSafeInteger(version) || version < 1 || !Number.isSafeInteger(intake.get("review_revision") ?? 0)) {
        throw new ClientIntakeError(503, "Intake version metadata needs attention.");
      }
      if (review.expectedVersion !== undefined && review.expectedVersion !== version) {
        throw new ClientIntakeError(400, "The intake version changed. Reload before reviewing.");
      }
      if (intake.get("status") === "draft") throw new ClientIntakeError(400, "Only submitted intake versions can be reviewed.");
      if (intake.get("review_action") === review.action && (intake.get("review_note") ?? null) === review.note && intake.get("reviewed_by_id") === dietitianId) {
        return { data: parseIntake(clientId, intake.data()) };
      }
      const revision = (intake.get("review_revision") ?? 0) + 1;
      const updatedAt = Timestamp.now();
      transaction.update(intakeReference, {
        status: review.status,
        review_action: review.action,
        review_note: review.note ?? FieldValue.delete(),
        review_updated_at: updatedAt,
        reviewed_by_id: dietitianId,
        review_revision: revision,
      });
      transaction.create(this.firestore.collection("intake_review_history").doc(`${clientId}_v${version}_r${revision}`), {
        client_id: clientId, version, revision, reviewed_by_id: dietitianId, action: review.action,
        status: review.status, note: review.note, reviewed_at: updatedAt,
      });
      const auditInput = {
        actor: context.actor,
        action: review.action === "reviewed"
          ? "intake.reviewed" as const
          : "intake.information_requested" as const,
        targetType: "intake" as const,
        targetId: clientId,
        clientId,
        dietitianId,
        status: review.status,
        outcome: "succeeded" as const,
        correlationId: context.correlationId,
        version,
        operationId: createHash("sha256").update(`${clientId}:${version}:${revision}`).digest("hex"),
      };
      if (review.action === "reviewed") this.audit.appendInTransaction(transaction, auditInput);
      else this.audit.appendWithEvent(transaction, auditInput, "intake.information_requested");
      return { data: parseIntake(clientId, {
        ...intake.data(),
        status: review.status,
        review_action: review.action,
        review_note: review.note,
        review_updated_at: updatedAt,
        reviewed_by_id: dietitianId,
      }) };
    }, context.correlationId);
  }
}

function requireAssignment(
  assignment: DocumentSnapshot,
  dietitianId: string,
): void {
  if (!assignment.exists || assignment.get("active") !== true ||
      assignment.get("dietitian_id") !== dietitianId) {
    throw new ClientIntakeError(
      403,
      "This client is not currently assigned to you.",
    );
  }
}

function parseIntake(
  clientId: string,
  data: DocumentData | undefined,
): ClientIntakeRecord {
  if (data === undefined ||
      (data.client_id !== undefined && data.client_id !== clientId)) {
    throw invalidIntake();
  }

  const sections: ClientIntakeSection[] = [];
  addSection(sections, "Health information", data.health_information);
  addSection(sections, "Goals", data.goals);
  addSection(
    sections,
    "Restrictions",
    data.restrictions ?? data.dietary_restrictions,
  );
  addSection(sections, "Additional information", data.responses);

  const remaining: DocumentData = {};
  for (const [key, value] of Object.entries(data)) {
    if (!reservedKeys.has(key)) remaining[key] = value;
  }
  addSection(sections, "Other intake information", remaining);

  return {
    version: Number.isSafeInteger(data.version) && data.version > 0 ? data.version : 1,
    clientId,
    allergies: stringList(data.allergies ?? data.food_allergies),
    medicalConditions: stringList(
      data.medical_conditions ?? data.health_conditions,
    ),
    sections,
    submittedAt: dateValue(data.submitted_at),
    updatedAt: dateValue(data.updated_at),
    status: intakeStatus(data.status, data.review_action),
    review: {
      action: reviewAction(data.review_action),
      note: optionalText(data.review_note),
      updatedAt: dateValue(data.review_updated_at),
    },
  };
}

function intakeStatus(
  value: unknown,
  actionValue: unknown,
): ClientIntakeStatus {
  if (value === "reviewed" || value === "information_requested") return value;
  const action = reviewAction(actionValue);
  if (action === "reviewed") return "reviewed";
  if (action === "missing_information" ||
      action === "clarification_requested") {
    return "information_requested";
  }
  return "submitted";
}

function reviewAction(value: unknown): ClientIntakeReviewAction | null {
  return value === "reviewed" || value === "missing_information" ||
      value === "clarification_requested"
    ? value
    : null;
}

function optionalText(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string") throw invalidIntake();
  return value.trim() || null;
}

function addSection(
  sections: ClientIntakeSection[],
  title: string,
  value: unknown,
): void {
  const fields = intakeFields(title, value);
  if (fields.length > 0) sections.push({ title, fields });
}

function intakeFields(defaultLabel: string, value: unknown): ClientIntakeField[] {
  if (value === null || value === undefined) return [];
  if (isPlainObject(value)) {
    return Object.entries(value).flatMap(([key, entry]) => {
      const formatted = displayValue(entry);
      return formatted === null
        ? []
        : [{ label: displayLabel(key), value: formatted }];
    });
  }
  const formatted = displayValue(value);
  return formatted === null
    ? []
    : [{ label: defaultLabel, value: formatted }];
}

function displayValue(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (typeof value === "string") return value.trim() || null;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  if (Array.isArray(value)) {
    const values = value
      .map(displayValue)
      .filter((entry): entry is string => entry !== null);
    return values.length === 0 ? null : values.join(", ");
  }
  if (isPlainObject(value)) {
    const values = Object.entries(value).flatMap(([key, entry]) => {
      const formatted = displayValue(entry);
      return formatted === null ? [] : [`${displayLabel(key)}: ${formatted}`];
    });
    return values.length === 0 ? null : values.join("; ");
  }
  throw invalidIntake();
}

function stringList(value: unknown): string[] {
  if (value === null || value === undefined) return [];
  const values = Array.isArray(value) ? value : [value];
  return values.flatMap(entry => {
    if (typeof entry !== "string") throw invalidIntake();
    const trimmed = entry.trim();
    return trimmed ? [trimmed] : [];
  });
}

function dateValue(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (typeof value === "string" && !Number.isNaN(Date.parse(value))) {
    return new Date(value).toISOString();
  }
  throw invalidIntake();
}

function displayLabel(key: string): string {
  const words = key
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[_-]+/g, " ")
    .trim();
  if (!words) throw invalidIntake();
  return words[0]!.toUpperCase() + words.slice(1);
}

function isPlainObject(value: unknown): value is DocumentData {
  return typeof value === "object" && value !== null &&
    !Array.isArray(value) && !(value instanceof Timestamp);
}

function invalidIntake(): ClientIntakeError {
  return new ClientIntakeError(
    503,
    "The saved client intake form needs attention.",
  );
}

function parseSavedAnswers(value: unknown) {
  try {
    return parseIntakeAnswers(value);
  } catch (error) {
    if (error instanceof IntakeAnswerError) throw invalidIntake();
    throw error;
  }
}
