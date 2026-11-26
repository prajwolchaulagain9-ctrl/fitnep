import { FieldPath, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { AccountInputError, accountFrom, accountMatchesActor, getCurrentAssignment } from "./account_service";
import { FirestoreAuditWriter } from "./audit";
import { healthAuditTarget } from "./audited_health_reads";
import { PermissionDeniedError } from "./authorization_policy";
import { submittedIntakeStatus } from "./client_intake_service";
import { AuthenticatedUser } from "./domain";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { FirestorePackageService } from "./package_membership_service";
import { FirestorePrivacyAcceptanceStore } from "./privacy_policy_acceptance";

const planFilters = ["no_plan", "draft", "submitted", "returned", "approved", "published"] as const;
type PlanFilter = typeof planFilters[number];
type PlanStatus = PlanFilter | "unavailable";

export async function listAssignedDietitianClients(
  db: Firestore, actor: AuthenticatedUser, query: Record<string, unknown>,
  after: string | undefined, correlationId: string,
) {
  if (actor.role !== "dietitian") throw new PermissionDeniedError();
  const { search, planFilter, limit } = parseQuery(query);
  const assignments = db.collection("client_assignments").where("dietitian_id", "==", actor.uid)
    .orderBy(FieldPath.documentId());
  const packages = new FirestorePackageService(db);
  const acceptance = new FirestorePrivacyAcceptanceStore(db);
  const privacy = new FirestorePrivacyPreferencesRepository(db);
  const audit = new FirestoreAuditWriter(db);

  return db.runTransaction(async transaction => {
    const actorSnapshot = await transaction.get(db.collection("users").doc(actor.uid));
    if (!accountMatchesActor(accountFrom(actor.uid, actorSnapshot.data()), actor)) {
      throw new PermissionDeniedError();
    }
    const load = async (id: string) => {
      const assignment = await getCurrentAssignment(db, id, transaction);
      if (!assignment || assignment.team.dietitianId !== actor.uid) return null;
      const { client, data, lastActivityAt } = assignment;
      if (search && !normalizedName(client.full_name).includes(search)) return null;
      const [accepted, sharing] = await Promise.all([
        acceptance.hasCurrentAcceptance(id, transaction), privacy.getForClient(id, transaction),
      ]);
      const shared = accepted && sharing.shareNutritionRecords;
      const plan = shared ? await latestPlan(db, transaction, id) : null;
      const planStatus: PlanStatus = shared ? (plan?.status ?? "no_plan") : "unavailable";
      if (planFilter && planStatus !== planFilter) return null;
      return { client, data, lastActivityAt, plan, planStatus, shared };
    };

    const scanSize = 25;
    let position = after;
    const matches: NonNullable<Awaited<ReturnType<typeof load>>>[] = [];
    // Cursors anchor the last returned client ID so sparse filters and
    // reassignment cannot skip still-visible matches on the following page.
    while (matches.length <= limit) {
      const page = await transaction.get((position ? assignments.startAfter(position) : assignments).limit(scanSize));
      const rows = await Promise.all(page.docs.map(doc => load(doc.id)));
      for (const row of rows) if (row) matches.push(row);
      if (page.size < scanSize) break;
      position = page.docs.at(-1)!.id;
    }
    const page = matches.slice(0, limit);
    const summaries = await Promise.all(page.map(async entry => {
      const id = entry.client.id;
      const [packageStatus, intake] = await Promise.all([
        packages.assignmentStatus(id, transaction),
        entry.shared ? currentIntake(db, transaction, id) : null,
      ]);
      return { entry, row: {
        id, full_name: entry.client.full_name, email: entry.client.email,
        package_status: packageStatus, plan_status: entry.planStatus,
        intake_status: intake?.status ?? null,
        last_activity_at: latestDate(
          entry.lastActivityAt, entry.data.assigned_at, entry.data.updated_at,
          entry.plan?.updatedAt, intake?.updatedAt,
        ),
      } };
    }));

    for (const { entry, row } of summaries) {
      if (!entry.shared) continue;
      const clientId = entry.client.id;
      const details = { actor, action: "health.read", outcome: "succeeded", correlationId, dietitianId: actor.uid } as const;
      audit.appendInTransaction(transaction, {
        ...details, ...healthAuditTarget({ clientId, category: "diet-plans" }),
        recordIds: entry.plan ? [entry.plan.id] : [],
      });
      if (row.intake_status !== null) {
        audit.appendInTransaction(transaction, {
          ...details, ...healthAuditTarget({ clientId, category: "intakes", recordId: clientId }),
        });
      }
    }

    const clients = summaries.map(({ row }) => row);
    return { clients, next_cursor: matches.length > limit ? clients.at(-1)!.id : null };
  });
}

function parseQuery(query: Record<string, unknown>) {
  const { search, plan_status, limit } = query;
  if (Object.keys(query).some(key => !["search", "plan_status", "limit", "after"].includes(key)) ||
      (search !== undefined && (typeof search !== "string" || search.length > 120))) {
    throw new AccountInputError("Use a client name of up to 120 characters and supported list filters.");
  }
  if (plan_status !== undefined && !isPlanFilter(plan_status)) {
    throw new AccountInputError("Invalid plan status filter.");
  }
  if (limit !== undefined && (typeof limit !== "string" || !/^(?:[1-9]|[1-4][0-9]|50)$/.test(limit))) {
    throw new AccountInputError("Choose a page size between 1 and 50.");
  }
  return {
    search: typeof search === "string" ? normalizedName(search) : "",
    planFilter: plan_status,
    limit: limit === undefined ? 50 : Number(limit),
  };
}

function normalizedName(value: string) {
  return value.normalize("NFKC").toLowerCase().trim().replace(/\s+/g, " ");
}

function isPlanFilter(value: unknown): value is PlanFilter {
  return planFilters.some(status => status === value);
}

async function latestPlan(db: Firestore, transaction: Transaction, clientId: string) {
  const plans = await transaction.get(db.collection("diet_plans").where("client_id", "==", clientId)
    .select("status", "updated_at", "created_at", "published_at").orderBy(FieldPath.documentId(), "desc"));
  let latest: { id: string; status: PlanStatus; updatedAt: string | null } | null = null;
  for (const plan of plans.docs) {
    const updatedAt = latestDate(plan.get("updated_at"), plan.get("created_at"), plan.get("published_at"));
    if (latest && (updatedAt ?? "") <= (latest.updatedAt ?? "")) continue;
    const status: unknown = plan.get("status");
    latest = { id: plan.id, status: isPlanFilter(status) && status !== "no_plan" ? status : "unavailable", updatedAt };
  }
  return latest;
}

async function currentIntake(db: Firestore, transaction: Transaction, clientId: string) {
  const [record] = await transaction.getAll(db.collection("client_intakes").doc(clientId), {
    fieldMask: ["client_id", "status", "updated_at", "submitted_at", "review_action", "review_updated_at"],
  });
  if (!record?.exists || record.get("status") === "draft") return null;
  const owner = record.get("client_id");
  if (owner !== undefined && owner !== clientId) return null;
  return {
    status: submittedIntakeStatus(record.get("status"), record.get("review_action")),
    updatedAt: latestDate(record.get("updated_at"), record.get("submitted_at"), record.get("review_updated_at")),
  };
}

function latestDate(...values: unknown[]): string | null {
  const latest = Math.max(...values.map(value => {
    const millis = value instanceof Timestamp ? value.toMillis() : typeof value === "string" ? Date.parse(value) : NaN;
    return Number.isFinite(millis) ? millis : -Infinity;
  }));
  return Number.isFinite(latest) ? new Date(latest).toISOString() : null;
}
