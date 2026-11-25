import {
  DocumentData,
  DocumentSnapshot,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

import { AuditWriter, FirestoreAuditWriter } from "./audit";

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
]);

export class FirestoreClientIntakeRepository implements ClientIntakeRepository {
  constructor(
    private readonly firestore: Firestore,
    private readonly audit: Pick<AuditWriter, "appendInTransaction"> =
      new FirestoreAuditWriter(firestore),
  ) {}

  getForAssignedDietitian(
    clientId: string,
    dietitianId: string,
  ): Promise<ClientIntakeRecord> {
    return this.firestore.runTransaction(async transaction => {
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
      return parseIntake(clientId, intake.data());
    });
  }

  updateReviewForAssignedDietitian(
    clientId: string,
    dietitianId: string,
    review: ClientIntakeReviewUpdate,
    context: ClientIntakeReviewContext,
  ): Promise<ClientIntakeRecord> {
    return this.firestore.runTransaction(async transaction => {
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

      const updatedAt = Timestamp.now();
      transaction.update(intakeReference, {
        status: review.status,
        review_action: review.action,
        review_note: review.note ?? FieldValue.delete(),
        review_updated_at: updatedAt,
        reviewed_by_id: dietitianId,
      });
      this.audit.appendInTransaction(transaction, {
        actor: context.actor,
        action: review.action === "reviewed"
          ? "intake.reviewed"
          : "intake.information_requested",
        targetType: "intake",
        targetId: clientId,
        clientId,
        dietitianId,
        status: review.status,
        outcome: "succeeded",
        correlationId: context.correlationId,
      });
      return parseIntake(clientId, {
        ...intake.data(),
        status: review.status,
        review_action: review.action,
        review_note: review.note,
        review_updated_at: updatedAt,
        reviewed_by_id: dietitianId,
      });
    });
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
