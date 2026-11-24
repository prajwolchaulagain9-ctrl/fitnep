import { FieldValue, Firestore, Transaction } from "firebase-admin/firestore";
import { createHash } from "node:crypto";

import { AuthenticatedUser, isUserRole } from "./domain";

export const auditActions = [
  "session.started", "session.ended", "auth.login", "access.denied", "health.read",
  "account.created", "account.updated", "account.role_changed",
  "account.deactivated", "account.reactivated", "privacy.accepted", "privacy.updated",
  "membership.selected", "membership.activated", "payment.submitted",
  "payment.verified", "payment.rejected", "payment.adjusted",
  "client.assigned", "client.reassigned", "intake.submitted", "intake.revised",
  "intake.reviewed", "intake.information_requested",
  "plan.created", "plan.submitted", "plan.returned", "plan.approved",
  "plan.published", "plan.revised",
] as const;
export type AuditAction = (typeof auditActions)[number];

export const workflowEventTypes = [
  "payment.verified", "payment.rejected", "membership.activated",
  "client.assigned", "client.reassigned", "intake.submitted", "intake.revised",
  "intake.information_requested",
] as const;
export type WorkflowEventType = (typeof workflowEventTypes)[number];

export interface AuditEventInput {
  actor: AuthenticatedUser;
  action: AuditAction;
  targetType: "account" | "membership" | "package" | "payment" | "assignment" |
    "intake" | "plan" | "health_record" | "record_collection" | "api";
  targetId: string;
  outcome: "succeeded" | "denied" | "failed";
  correlationId: string;
  operationId?: string;
  clientId?: string;
  dietitianId?: string;
  previousDietitianId?: string;
  status?: string;
  version?: number;
  recordIds?: readonly string[];
}

export interface AuditWriter {
  append(input: AuditEventInput): Promise<string>;
  appendInTransaction(transaction: Transaction, input: AuditEventInput): string;
  appendWithEvent(
    transaction: Transaction, input: AuditEventInput, eventType: WorkflowEventType,
  ): string;
}

export class AuditUnavailableError extends Error {
  constructor() { super("Audit storage is temporarily unavailable."); }
}

/** Backend-only metadata writer: there is no update/delete or arbitrary payload. */
export class FirestoreAuditWriter implements AuditWriter {
  constructor(private readonly firestore: Firestore) {}

  async append(input: AuditEventInput): Promise<string> {
    const reference = this.firestore.collection("audit_events").doc();
    const data = auditData(input);
    try {
      await reference.create({ id: reference.id, ...data });
      return reference.id;
    } catch {
      throw new AuditUnavailableError();
    }
  }

  appendInTransaction(transaction: Transaction, input: AuditEventInput): string {
    const reference = this.firestore.collection("audit_events").doc();
    transaction.create(reference, { id: reference.id, ...auditData(input) });
    return reference.id;
  }

  appendWithEvent(
    transaction: Transaction, input: AuditEventInput, eventType: WorkflowEventType,
  ): string {
    if (!workflowEventTypes.includes(eventType) || input.action !== eventType ||
      input.outcome !== "succeeded" || !input.operationId) {
      throw new Error("A committed workflow event requires its matching audit action and operation ID.");
    }
    const data = auditData(input);
    const id = createHash("sha256").update(JSON.stringify([
      data.actor_id, data.operation_id, eventType, data.target_type, data.target_id, data.version ?? null,
    ])).digest("hex");
    const reference = this.firestore.collection("audit_events").doc(id);
    transaction.create(reference, { id: reference.id, ...data });
    // Immutable envelope and mutable delivery state live in separate documents.
    transaction.create(this.firestore.collection("workflow_outbox").doc(reference.id), {
      event_id: reference.id,
      event_type: eventType,
      audit_id: reference.id,
      ...data,
    });
    transaction.create(this.firestore.collection("outbox_deliveries").doc(reference.id), {
      event_id: reference.id,
      state: "pending",
      attempt_count: 0,
      next_attempt_at: FieldValue.serverTimestamp(),
    });
    return reference.id;
  }
}

function auditData(input: AuditEventInput): Record<string, unknown> {
  const allowed = ["actor", "action", "targetType", "targetId", "outcome", "correlationId",
    "operationId", "clientId", "dietitianId", "previousDietitianId", "status",
    "version", "recordIds"];
  if (Object.keys(input).some(key => !allowed.includes(key)) ||
    !auditActions.includes(input.action) || !isUserRole(input.actor?.role) ||
    !["succeeded", "denied", "failed"].includes(input.outcome) ||
    !["account", "membership", "package", "payment", "assignment", "intake",
      "plan", "health_record", "record_collection", "api"].includes(input.targetType)) {
    throw new Error("Invalid audit metadata.");
  }
  const data: Record<string, unknown> = {
    actor_id: boundedString(input.actor.uid, 128),
    actor_name: boundedString(input.actor.displayName ?? input.actor.uid, 320),
    actor_role: input.actor.role,
    action: input.action,
    target_type: input.targetType,
    target_id: boundedString(input.targetId, 512),
    outcome: input.outcome,
    correlation_id: boundedString(input.correlationId, 128),
    occurred_at: FieldValue.serverTimestamp(),
  };
  for (const [key, value] of [
    ["operation_id", input.operationId], ["client_id", input.clientId],
    ["dietitian_id", input.dietitianId],
    ["previous_dietitian_id", input.previousDietitianId],
  ] as const) {
    if (value !== undefined) data[key] = boundedString(value, 128);
  }
  if (input.status !== undefined) {
    if (!/^[a-z][a-z0-9_]{0,39}$/.test(input.status)) throw new Error("Invalid audit status.");
    data.status = input.status;
  }
  if (input.version !== undefined) {
    if (!Number.isSafeInteger(input.version) || input.version < 1) throw new Error("Invalid audit version.");
    data.version = input.version;
  }
  if (input.recordIds !== undefined) {
    if (!Array.isArray(input.recordIds) || input.recordIds.length > 50) throw new Error("Invalid audit record IDs.");
    data.record_ids = input.recordIds.map(id => boundedString(id, 128));
  }
  return data;
}

function boundedString(value: unknown, maximum: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > maximum ||
    /[\u0000-\u001f\u007f]/.test(value)) {
    throw new Error("Invalid audit identifier or display name.");
  }
  return value;
}
