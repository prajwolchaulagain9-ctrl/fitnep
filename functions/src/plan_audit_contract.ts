import { createHash } from "node:crypto";
import { FieldValue, Firestore, Transaction } from "firebase-admin/firestore";
import { accountFrom, accountMatchesActor, identifier } from "./account_service";
import { AuditWriter, FirestoreAuditWriter } from "./audit";
import { AuthenticatedUser } from "./domain";
import { PermissionDeniedError } from "./authorization_policy";

export const planEvents = ["created", "submitted", "returned", "approved", "published", "revised"] as const;
export type PlanEvent = typeof planEvents[number];
const eventStatuses: Record<PlanEvent, string> = {
  created: "draft", submitted: "submitted", returned: "returned", approved: "approved", published: "published", revised: "draft",
};

/** Internal producer contract only; no client endpoint creates plan decisions. */
export class PlanAuditContract {
  constructor(private readonly db: Firestore, private readonly audit: AuditWriter = new FirestoreAuditWriter(db)) {}

  async append(transaction: Transaction, actor: AuthenticatedUser,
    input: { planId: string; version: number; event: PlanEvent; operationId: string; correlationId: string }) {
    const allowed = ["planId", "version", "event", "operationId", "correlationId"];
    if (Object.keys(input).some(key => !allowed.includes(key)) || !planEvents.includes(input.event) ||
        !Number.isSafeInteger(input.version) || input.version < 1) throw new Error("Invalid plan event contract.");
    identifier(input.planId);
    identifier(input.operationId);
    const versionRef = this.db.doc(`diet_plans/${input.planId}/versions/${input.version}`);
    const receiptId = createHash("sha256").update(JSON.stringify([input.planId, input.version, input.event, input.operationId])).digest("hex");
    const receiptRef = this.db.doc(`plan_event_receipts/${receiptId}`);
    const [version, account, receipt] = await Promise.all([
      transaction.get(versionRef), transaction.get(this.db.doc(`users/${actor.uid}`)), transaction.get(receiptRef),
    ]);
    if (!accountMatchesActor(accountFrom(actor.uid, account.data()), actor) || !["dietitian", "admin"].includes(actor.role)) {
      throw new PermissionDeniedError();
    }
    const stored = version.data();
    // Actor/owner/status/version come from the stored producer state, never a request body.
    if (!stored || stored.version !== input.version || stored.plan_id !== input.planId ||
        stored.status !== eventStatuses[input.event] || stored.last_event !== input.event || stored.last_actor_id !== actor.uid ||
        stored.operation_id !== input.operationId || typeof stored.client_id !== "string" || typeof stored.dietitian_id !== "string") {
      throw new Error("Plan producer state does not match the event.");
    }
    identifier(stored.client_id); identifier(stored.dietitian_id);
    if (receipt.exists) {
      if (receipt.get("actor_id") !== actor.uid) throw new PermissionDeniedError();
      return receipt.get("audit_id") as string;
    }
    const eventId = this.audit.appendInTransaction(transaction, {
      actor, action: `plan.${input.event}`, targetType: "plan", targetId: input.planId,
      clientId: stored.client_id, dietitianId: stored.dietitian_id, version: stored.version,
      status: stored.status, outcome: "succeeded", operationId: input.operationId, correlationId: input.correlationId,
    });
    transaction.create(receiptRef, { audit_id: eventId, actor_id: actor.uid, plan_id: input.planId,
      version: stored.version, event: input.event, occurred_at: FieldValue.serverTimestamp() });
    return eventId;
  }
}
