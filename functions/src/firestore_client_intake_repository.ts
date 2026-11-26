import {
  DocumentData,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";

import { AuditWriter, FirestoreAuditWriter } from "./audit";
import { getCurrentAssignment } from "./account_service";
import {
  ageRequiresGuardian, IntakeAnswerError, IntakeAnswers, parseIntakeAnswers, validateIntakeSubmission,
} from "./client_intake_answers";
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
  IntakeDraftWrite,
  IntakeSubmission,
  IntakeWorkspace,
  submittedIntakeStatus,
} from "./client_intake_service";

const reservedKeys = new Set([
  "answers",
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

  getSubmittedIntake(actor: AuthenticatedUser, clientId: string, correlationId: string, version?: number) {
    return this.readFor(actor, clientId, correlationId, version);
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
      // A response can be lost after the transaction commits. Return the
      // saved answers only when they match the very next draft revision.
      if (draft.exists && workspace.version === input.expectedVersion &&
          workspace.draftRevision === input.expectedDraftRevision + 1 &&
          JSON.stringify(workspace.answers) === JSON.stringify(input.answers)) {
        return { data: workspace };
      }
      requireEditableWorkspace(workspace, input);
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

  submit(actor: AuthenticatedUser, input: IntakeSubmission, correlationId: string): Promise<IntakeWorkspace> {
    return this.reads.readResource(actor, {
      clientId: actor.uid, category: "intakes", recordId: "submitted", ownerOnly: true,
    }, async transaction => {
      const { workspace, intake, draft, acceptance } = await this.loadWorkspace(transaction, actor);
      const operationId = createHash("sha256").update(input.requestId).digest("hex");
      const receiptRef = intake.ref.collection("submissions").doc(operationId);
      const receipt = await transaction.get(receiptRef);
      const fingerprint = createHash("sha256").update(JSON.stringify([
        input.expectedVersion, input.expectedDraftRevision, input.guardianConfirmed, input.answers,
      ])).digest("hex");
      if (receipt.exists) {
        if (receipt.get("fingerprint") !== fingerprint) {
          throw new ClientIntakeError(409, "This request ID was used for different intake answers.");
        }
        return { data: workspace };
      }

      requireEditableWorkspace(workspace, input);
      const now = Timestamp.now();
      let bmi: number;
      try {
        bmi = validateIntakeSubmission(input.answers, now.toDate());
      } catch (error) {
        if (error instanceof IntakeAnswerError) throw new ClientIntakeError(400, error.message);
        throw error;
      }
      const versions = intake.ref.collection("versions");
      const [previous, assignment] = await Promise.all([
        workspace.version === 0 ? null : transaction.get(versions.doc(String(workspace.version))),
        getCurrentAssignment(this.firestore, actor.uid, transaction),
      ]);
      const guardianConfirmed = this.confirmGuardian(transaction, actor, acceptance, input, correlationId);
      const version = workspace.version + 1;
      const submitted = submittedData(actor.uid, input.answers, version, bmi, now);
      // Preserve records written before immutable version documents existed.
      if (previous && !previous.exists) {
        transaction.create(previous.ref, {
          ...intake.data(),
          client_id: actor.uid,
          version: workspace.version,
        });
      }
      transaction.create(versions.doc(String(version)), submitted);
      transaction.set(intake.ref, submitted);
      if (draft.exists) transaction.delete(draft.ref);
      transaction.create(receiptRef, { version, fingerprint });
      const action = workspace.version === 0 ? "intake.submitted" : "intake.revised";
      this.audit.appendWithEvent(transaction, {
        actor, action, targetType: "intake", targetId: actor.uid, clientId: actor.uid,
        ...(assignment ? { dietitianId: assignment.team.dietitianId } : {}),
        version, status: "submitted", outcome: "succeeded", correlationId, operationId,
      }, action);
      return { data: {
        ...workspace, answers: input.answers, version, draftRevision: 0,
        latest: parseIntake(actor.uid, submitted), guardianConfirmed,
      } };
    }, correlationId);
  }

  private async loadWorkspace(transaction: Transaction, actor: AuthenticatedUser) {
    const acceptance = await this.currentAcceptance(transaction, actor.uid);
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
    return { workspace, intake, draft, acceptance };
  }

  private async currentAcceptance(transaction: Transaction, uid: string) {
    const acceptance = await transaction.get(this.firestore.doc(`privacy_acceptances/${uid}`));
    if (!hasValidPrivacyAcceptance(acceptance.data())) {
      throw new ClientIntakeError(403, "A current privacy acceptance is required to open intake.");
    }
    return acceptance;
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

  private readFor(actor: AuthenticatedUser, clientId: string, correlationId?: string, version?: number) {
    return this.reads.readResource(actor, {
      clientId, category: "intakes", recordId: "submitted", version,
    }, async transaction => {
      if (actor.role === "client") await this.currentAcceptance(transaction, clientId);
      const reference = this.firestore.doc(`client_intakes/${clientId}`);
      const current = await transaction.get(reference);
      const intake = version === undefined || (current.get("version") ?? 1) === version
        ? current
        : await transaction.get(reference.collection("versions").doc(String(version)));
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
      const currentRevision = intake.get("review_revision") ?? 0;
      if (!Number.isSafeInteger(version) || version < 1 || !Number.isSafeInteger(currentRevision) || currentRevision < 0) {
        throw new ClientIntakeError(503, "Intake version metadata needs attention.");
      }
      const needsVersion = intake.get("answers") !== undefined;
      if (needsVersion && review.expectedVersion === undefined) {
        throw new ClientIntakeError(400, "Supply the version of the submitted intake being reviewed.");
      }
      if (review.expectedVersion !== undefined && review.expectedVersion !== version) {
        throw new ClientIntakeError(409, "The intake version changed. Reload before reviewing.");
      }
      if (intake.get("status") === "draft") throw new ClientIntakeError(400, "Only submitted intake versions can be reviewed.");
      const sameReview = intake.get("review_action") === review.action &&
        (intake.get("review_note") ?? null) === review.note && intake.get("reviewed_by_id") === dietitianId;
      const expectedRevision = review.expectedReviewRevision;
      if (sameReview && (expectedRevision === undefined || expectedRevision === currentRevision ||
          expectedRevision + 1 === currentRevision)) {
        return { data: parseIntake(clientId, intake.data()) };
      }
      if (expectedRevision !== undefined && expectedRevision !== currentRevision) {
        throw new ClientIntakeError(409, "This intake was reviewed elsewhere. Reload before reviewing.");
      }
      const revision = currentRevision + 1;
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
        review_revision: revision,
      }) };
    }, context.correlationId);
  }
}

function requireEditableWorkspace(workspace: IntakeWorkspace, input: IntakeDraftWrite): void {
  if (workspace.version !== input.expectedVersion || workspace.draftRevision !== input.expectedDraftRevision) {
    throw new ClientIntakeError(409, "Your intake changed. Reload the saved form before trying again.");
  }
  if (!workspace.membershipActive) {
    throw new ClientIntakeError(409, "An active membership is required to update the intake form.");
  }
}

function submittedData(
  clientId: string, answers: IntakeAnswers, version: number, bmi: number, now: Timestamp,
): DocumentData {
  return {
    client_id: clientId,
    answers,
    version,
    status: "submitted",
    submitted_at: now,
    updated_at: now,
    health_information: {
      age: Number(answers.age),
      date_of_birth: answers.date_of_birth,
      height_cm: Number(answers.height_cm),
      weight_kg: Number(answers.weight_kg),
      ...(answers.waist_cm ? { waist_cm: Number(answers.waist_cm) } : {}),
      ...(answers.hip_cm ? { hip_cm: Number(answers.hip_cm) } : {}),
      ...(answers.chest_cm ? { chest_cm: Number(answers.chest_cm) } : {}),
      BMI: bmi,
    },
    allergies: reportedItems(answers.allergies!),
    medical_conditions: reportedItems(answers.medical_history!),
    goals: { fitness_goals: answers.fitness_goals },
    restrictions: { dietary_restrictions: answers.dietary_restrictions },
    responses: {
      full_name: answers.full_name,
      ...(answers.contact_email ? { contact_email: answers.contact_email } : {}),
      ...(answers.contact_phone ? { contact_phone: answers.contact_phone } : {}),
      food_preferences: answers.food_preferences,
    },
  };
}

function reportedItems(answer: string): string[] {
  return answer.toLowerCase() === "none" ? [] : [answer];
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
    reviewRevision: Number.isSafeInteger(data.review_revision) && data.review_revision >= 0 ? data.review_revision : 0,
    clientId,
    allergies: stringList(data.allergies ?? data.food_allergies),
    medicalConditions: stringList(
      data.medical_conditions ?? data.health_conditions,
    ),
    sections,
    submittedAt: dateValue(data.submitted_at),
    updatedAt: dateValue(data.updated_at),
    status: submittedIntakeStatus(data.status, data.review_action),
    review: {
      action: reviewAction(data.review_action),
      note: optionalText(data.review_note),
      updatedAt: dateValue(data.review_updated_at),
    },
  };
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
