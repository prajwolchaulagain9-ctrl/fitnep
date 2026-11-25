import {
  DocumentData,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import { AuditWriter, FirestoreAuditWriter } from "./audit";
import { AuthenticatedUser } from "./domain";
import { FirestorePrivateRecordsStore } from "./firestore_private_records_store";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
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
