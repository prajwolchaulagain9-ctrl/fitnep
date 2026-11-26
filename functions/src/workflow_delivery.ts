import { randomUUID } from "node:crypto";
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { getCurrentAssignment } from "./account_service";
import { workflowEventTypes, WorkflowEventType } from "./audit";
import { NewNotification } from "./domain";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { Auth } from "firebase-admin/auth";
import { reconcileAccountAuth } from "./account_auth_recovery";

type IntakeWorkflowEventType = Extract<WorkflowEventType, `intake.${string}`>;

interface IntakeWorkflowNotificationInput {
  eventId: string;
  eventType: IntakeWorkflowEventType;
  clientId: string;
  createdAt: string;
  dietitianId?: string;
}

export function buildIntakeWorkflowNotification(
  input: IntakeWorkflowNotificationInput,
): NewNotification | null {
  const informationRequested =
    input.eventType === "intake.information_requested";
  const recipientId = informationRequested
    ? input.clientId
    : input.dietitianId;
  if (!recipientId) return null;

  return {
    id: input.eventId,
    recipientId,
    type: "intake",
    referenceId: input.clientId,
    eventKey: `outbox:${input.eventId}:${recipientId}`,
    title: informationRequested
      ? "Intake information requested"
      : "Client intake available",
    message: informationRequested
      ? "Additional or clearer information is required in your intake form. Open the form to review your dietitian's request."
      : "Open the intake form to view the update securely.",
    createdAt: input.createdAt,
  };
}

/** The durable queue is drained by the same single Node host as the API. */
export class HostedWorkflowDelivery {
  private running = false;
  constructor(private readonly db: Firestore, private readonly now = Date.now) {}

  async drain(): Promise<number> {
    if (this.running) return 0;
    this.running = true;
    let delivered = 0;
    try {
      const due = await this.db.collection("outbox_deliveries")
        .where("next_attempt_at", "<=", Timestamp.fromMillis(this.now()))
        .orderBy("next_attempt_at").limit(25).get();
      for (const document of due.docs) {
        const lease = randomUUID();
        const claimed = await this.db.runTransaction(async tx => {
          const current = (await tx.get(document.ref)).data();
          if (!current || current.state === "delivered" ||
              !(current.next_attempt_at instanceof Timestamp) || current.next_attempt_at.toMillis() > this.now()) return false;
          tx.update(document.ref, { state: "processing", lease_id: lease,
            next_attempt_at: Timestamp.fromMillis(this.now() + 60_000),
            attempt_count: (current.attempt_count ?? 0) + 1 });
          return true;
        });
        if (!claimed) continue;
        try {
          await this.deliver(document.id, lease);
          delivered++;
        } catch {
          await this.db.runTransaction(async tx => {
            const current = (await tx.get(document.ref)).data();
            if (current?.lease_id !== lease || current.state === "delivered") return;
            const delay = Math.min(300_000, 1000 * 2 ** Math.min(current.attempt_count, 8));
            tx.update(document.ref, { state: "retry", lease_id: FieldValue.delete(),
              next_attempt_at: Timestamp.fromMillis(this.now() + delay), last_error: "delivery-unavailable" });
          });
        }
      }
      return delivered;
    } finally { this.running = false; }
  }

  private deliver(id: string, lease: string) {
    return this.db.runTransaction(async tx => {
      const deliveryRef = this.db.doc(`outbox_deliveries/${id}`);
      const eventRef = this.db.doc(`workflow_outbox/${id}`);
      const receiptRef = this.db.doc(`outbox_handler_receipts/${id}`);
      const [delivery, snapshot, receipt] = await Promise.all([tx.get(deliveryRef), tx.get(eventRef), tx.get(receiptRef)]);
      if (delivery.get("lease_id") !== lease || delivery.get("state") !== "processing") return;
      const event = snapshot.data();
      if (!event || !workflowEventTypes.includes(event.event_type as WorkflowEventType) ||
          event.event_id !== id || event.audit_id !== id || !event.client_id ||
          !(event.occurred_at instanceof Timestamp)) throw new Error("Invalid trusted event.");
      if (!receipt.exists) {
        const notifications: NewNotification[] = [];
        const base = { id, createdAt: event.occurred_at.toDate().toISOString() };
        const assignment = await getCurrentAssignment(this.db, event.client_id, tx);
        if (event.event_type === "client.assigned" || event.event_type === "client.reassigned") {
          // Replays cannot notify the former team or expose medical content.
          if (assignment && assignment.data.version === event.version && assignment.team.dietitianId === event.dietitian_id) {
            const recipientId = assignment.team.dietitianId;
            notifications.push({ ...base, recipientId, type: "assignment", referenceId: event.client_id,
              eventKey: `client:${event.client_id}:assigned:${recipientId}:v${event.version}`,
              title: "New client assigned", message: "A client has been assigned to you. Open their profile to continue." });
            const intake = await tx.get(this.db.doc(`client_intakes/${event.client_id}`));
            if (intake.exists && intake.get("status") !== "draft") {
              notifications.push(intakeAvailableNotification(
                base, event.client_id, recipientId, event.version, intake.get("version") ?? 1,
              ));
            }
          }
        } else if (event.event_type.startsWith("intake.")) {
          const intakeRef = this.db.doc(`client_intakes/${event.client_id}`);
          const intake = await tx.get(intakeRef);
          const latestVersion = intake.get("version") ?? 1;
          if (intake.exists && intake.get("status") !== "draft") {
            if (event.event_type === "intake.information_requested") {
              if (latestVersion === event.version) {
                const notification = buildIntakeWorkflowNotification({
                  eventId: id,
                  eventType: event.event_type,
                  clientId: event.client_id,
                  createdAt: base.createdAt,
                });
                if (notification) notifications.push(notification);
              }
            } else if (assignment) {
              const recipientId = assignment.team.dietitianId;
              // An older event can still reach the dietitian assigned when it
              // was saved, provided that dietitian is still the current one.
              const available = latestVersion === event.version ||
                (recipientId === event.dietitian_id &&
                  (await tx.get(intakeRef.collection("versions").doc(String(event.version)))).exists);
              if (available) {
                notifications.push(intakeAvailableNotification(
                  base, event.client_id, recipientId, assignment.data.version ?? 1, event.version,
                ));
              }
            }
          }
        } else if (event.event_type === "membership.activated") {
          const membership = await tx.get(this.db.doc(`package_memberships/${event.target_id}`));
          if (membership.get("client_id") === event.client_id && membership.get("status") === "active") notifications.push({ ...base,
            recipientId: event.client_id, type: "membership", referenceId: event.target_id,
            eventKey: `outbox:${id}:${event.client_id}`, title: "Membership active", message: "Your membership is now active. View its dates and details." });
        } else {
          const payment = await tx.get(this.db.doc(`payments/${event.target_id}`));
          const owner = payment.get("recipient_id") ?? payment.get("client_id");
          const matches = event.event_type === "payment.verified"
            ? payment.get("verified") === true && ["verified", "paid", "confirmed", "succeeded"].includes(payment.get("status"))
            : payment.get("status") === "rejected";
          if (owner === event.client_id && matches) notifications.push({ ...base, recipientId: owner, type: "payment", referenceId: event.target_id,
            eventKey: event.event_type === "payment.verified" ? `payment:${event.target_id}:confirmed:${owner}` : `outbox:${id}:${owner}`,
            title: event.event_type === "payment.verified" ? "Payment confirmed" : "Payment update",
            message: "Open your payment details to view the decision." });
        }
        await new FirestoreNotificationRepository(this.db).createManyInTransaction(tx, notifications);
        tx.create(receiptRef, { event_id: id, handler: "notifications-v1", recipient_ids: notifications.map(n => n.recipientId),
          result: notifications.length ? "delivered" : "superseded", completed_at: FieldValue.serverTimestamp() });
      }
      tx.update(deliveryRef, { state: "delivered", delivered_at: FieldValue.serverTimestamp(),
        next_attempt_at: FieldValue.delete(), lease_id: FieldValue.delete(), last_error: FieldValue.delete() });
    });
  }
}

function intakeAvailableNotification(
  base: Pick<NewNotification, "id" | "createdAt">,
  clientId: string,
  recipientId: string,
  assignmentVersion: number,
  intakeVersion: number,
): NewNotification {
  return {
    ...base,
    recipientId,
    type: "intake",
    referenceId: clientId,
    // Assignment and intake events may both discover the same submission.
    eventKey: `intake:${clientId}:available:${recipientId}:assignment-${assignmentVersion}:v${intakeVersion}`,
    title: "Client intake available",
    message: "Open FitNEP for an update to your assigned client's intake.",
  };
}

/** No timer can guarantee delivery while a free instance is asleep. */
export function startWorkflowRecovery(db: Firestore, auth: Auth, recoverPhotos?: () => Promise<void>) {
  const worker = new HostedWorkflowDelivery(db);
  let recovering = false;
  const drain = () => {
    if (recovering) return;
    recovering = true;
    void (async () => {
      await reconcileAccountAuth(auth, db);
      await worker.drain();
      await recoverPhotos?.();
    })()
      .catch(() => console.error("Workflow recovery unavailable; persisted events will retry."))
      .finally(() => { recovering = false; });
  };
  drain();
  const timer = setInterval(drain, 30_000);
  timer.unref();
  return { worker, drain, stop: () => clearInterval(timer) };
}
