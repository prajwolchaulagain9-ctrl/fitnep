import { FieldPath, Firestore, Timestamp } from "firebase-admin/firestore";
import { AccountInputError, identifier } from "./account_service";
import { AuditAction, auditActions } from "./audit";

const pageSize = 50;
const batchSize = 100;
const dayMs = 24 * 60 * 60 * 1000;
const nepalOffsetMs = (5 * 60 + 45) * 60 * 1000;
const fields = [
  "actor_id", "actor_name", "actor_role", "action", "target_type", "target_id", "outcome",
  "occurred_at", "client_id", "dietitian_id", "previous_dietitian_id", "status", "version",
  "record_ids", "correlation_id",
];

function nepalDay(value: unknown): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || !/^[1-9]\d{3}-\d{2}-\d{2}$/.test(value)) {
    throw new AccountInputError("Supply audit dates in YYYY-MM-DD format.");
  }
  const midnight = Date.parse(value + "T00:00:00+05:45");
  if (!Number.isFinite(midnight) ||
      new Date(midnight + nepalOffsetMs).toISOString().slice(0, 10) !== value) {
    throw new AccountInputError("Supply valid Nepal calendar dates.");
  }
  return midnight;
}

export async function listAuditEvents(db: Firestore, filters: Record<string, unknown>) {
  const allowed = ["actor_id", "action", "client_id", "dietitian_id", "status", "from", "through", "plan_id", "after"];
  if (Object.keys(filters).some(key => !allowed.includes(key))) throw new AccountInputError("Unknown audit filter.");
  const { action, status, after, plan_id: plan } = filters;
  const from = nepalDay(filters.from);
  const through = nepalDay(filters.through);
  if (from !== undefined && through !== undefined && from > through) {
    throw new AccountInputError("The start date must come before or equal the end date.");
  }
  if (action !== undefined && !auditActions.includes(action as AuditAction)) {
    throw new AccountInputError("Unknown audit action.");
  }
  if (status !== undefined && (typeof status !== "string" || !/^[a-z][a-z0-9_]{0,39}$/.test(status))) {
    throw new AccountInputError("Supply a valid audit status.");
  }
  const equality: [string, string][] = [];
  for (const [key, value] of [
    ["target_id", plan], ["client_id", filters.client_id], ["dietitian_id", filters.dietitian_id],
    ["actor_id", filters.actor_id],
  ] as const) {
    if (value !== undefined) equality.push([key, identifier(value)]);
  }
  if (typeof action === "string") equality.push(["action", action]);
  if (typeof status === "string") equality.push(["status", status]);

  const collection = db.collection("audit_events");
  let query = collection.select(...fields).orderBy("occurred_at", "desc").orderBy(FieldPath.documentId(), "desc");
  // Apply the first exact match in Firestore and the rest in the API so combined
  // filters need one index per field. Cap each request and page through sparse matches.
  const [indexed, ...remaining] = equality;
  if (indexed) query = query.where(indexed[0], "==", indexed[1]);
  if (from !== undefined) query = query.where("occurred_at", ">=", Timestamp.fromMillis(from));
  if (through !== undefined) query = query.where("occurred_at", "<", Timestamp.fromMillis(through + dayMs));
  if (after !== undefined) {
    const cursor = await collection.doc(identifier(after)).get();
    if (!(cursor.get("occurred_at") instanceof Timestamp)) throw new AccountInputError("Invalid audit cursor.");
    query = query.startAfter(cursor);
  }
  const limit = remaining.length || plan !== undefined ? batchSize : pageSize;
  const batch = await query.limit(limit + 1).get();
  const scanned = batch.docs.slice(0, limit);
  const matches = scanned.filter(doc => remaining.every(([key, value]) => doc.get(key) === value) &&
    (plan === undefined || doc.get("target_type") === "plan"));
  const events = matches.slice(0, pageSize).map(doc => ({
    ...doc.data(), id: doc.id, occurred_at: (doc.get("occurred_at") as Timestamp).toDate().toISOString(),
  }));
  const next = matches.length > pageSize ? events.at(-1) : batch.size > limit ? scanned.at(-1) : undefined;
  return { events, next_cursor: next?.id ?? null };
}
