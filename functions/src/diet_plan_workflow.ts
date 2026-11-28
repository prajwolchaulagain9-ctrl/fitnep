import { createHash } from "node:crypto";
import { DocumentData, FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { AccountInputError, accountFrom, accountMatchesActor, assignmentIncludesActor,
  getCurrentAssignment, identifier } from "./account_service";
import { FirestoreAuditWriter } from "./audit";
import { PermissionDeniedError } from "./authorization_policy";
import { AuthenticatedUser } from "./domain";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { FirestorePrivacyAcceptanceStore } from "./privacy_policy_acceptance";

const transitions = {
  submit: { from: "draft", to: "submitted", role: "dietitian", event: "plan.submitted" },
  return: { from: "submitted", to: "returned", role: "admin", event: "plan.returned" },
  approve: { from: "submitted", to: "approved", role: "admin", event: "plan.approved" },
  publish: { from: "approved", to: "published", role: "dietitian", event: "plan.published" },
} as const;

export function publicDietPlan(id: string, data: DocumentData, owner: boolean) {
  const fields = owner && data.status !== "published" && data.status !== undefined ? data.published : data;
  if (!fields) return null;
  return { id, title: fields.title, description: fields.description, dietitian_name: fields.dietitian_name,
    status: fields.status ?? "published", version: fields.version ?? 1,
    ...(owner ? {} : { return_reason: fields.return_reason ?? null }),
    created_at: data.created_at instanceof Timestamp ? data.created_at.toDate().toISOString() : null };
}

export async function writeDietPlan(
  db: Firestore, actor: AuthenticatedUser, clientId: string, planId: string | undefined,
  input: Record<string, unknown>, correlationId: string,
) {
  const action = input.action;
  if (action !== undefined && (typeof action !== "string" || !Object.hasOwn(transitions, action) || !planId)) {
    throw new AccountInputError("Choose a valid plan action.");
  }
  const transition = action === undefined ? undefined : transitions[action as keyof typeof transitions];
  if (actor.role !== (transition?.role ?? "dietitian")) throw new PermissionDeniedError();
  const allowed = transition ? ["action", "version", "reason"] : ["title", "description", "draft", "version", "request_id"];
  if (Object.keys(input).some(key => !allowed.includes(key)) ||
      (input.draft !== undefined && typeof input.draft !== "boolean")) {
    throw new AccountInputError("The plan includes an unsupported field.");
  }
  const title = typeof input.title === "string" ? input.title.trim() : "";
  const description = typeof input.description === "string" ? input.description.trim() : "";
  const reason = typeof input.reason === "string" ? input.reason.trim() : "";
  if ((!transition && (!title || title.length > 120 || !description || description.length > 10000)) ||
      (action === "return" ? !reason || reason.length > 500 : input.reason !== undefined)) {
    throw new AccountInputError(action === "return" ? "Enter a reason up to 500 characters." : "Supply a title and a diet plan description.");
  }
  if ((transition || (input.draft && planId) || input.version !== undefined) &&
      (!Number.isSafeInteger(input.version) || Number(input.version) < 1)) {
    throw new AccountInputError("Reload the plan to get the current version.");
  }
  const requestId = input.request_id === undefined ? undefined : identifier(input.request_id);
  const scopedId = requestId ? createHash("sha256").update(JSON.stringify([actor.uid, clientId, requestId])).digest("hex") : undefined;
  const plans = db.collection("diet_plans");
  const ref = planId || scopedId ? plans.doc(planId ?? scopedId!) : plans.doc();
  const audit = new FirestoreAuditWriter(db);
  await db.runTransaction(async transaction => {
    const [accountDoc, assignment, current] = await Promise.all([
      transaction.get(db.doc(`users/${actor.uid}`)), getCurrentAssignment(db, clientId, transaction), transaction.get(ref),
    ]);
    const account = accountFrom(actor.uid, accountDoc.data());
    if (!accountMatchesActor(account, actor) || !assignment || !assignmentIncludesActor(actor, assignment) ||
        (current.exists && current.get("client_id") !== clientId) || (planId && !current.exists)) {
      throw new PermissionDeniedError();
    }
    // Reviewing a plan requires the same current consent as opening its contents.
    if (actor.role === "admin" || input.draft || transition) {
      const [accepted, sharing] = await Promise.all([
        new FirestorePrivacyAcceptanceStore(db).hasCurrentAcceptance(clientId, transaction),
        new FirestorePrivacyPreferencesRepository(db).getForClient(clientId, transaction),
      ]);
      if (!accepted || !sharing.shareNutritionRecords) throw new PermissionDeniedError();
    }
    if (!planId && current.exists) return; // Retry of the same scoped creation.
    const previous = current.data();
    const priorVersion = (previous?.version ?? 1) as number;
    const priorStatus = (previous?.status ?? "published") as string;
    if (input.version !== undefined && input.version !== priorVersion) {
      throw new AccountInputError("This plan version changed. Refresh before continuing.");
    }
    if (transition && priorStatus !== transition.from) {
      throw new AccountInputError("This plan status changed. Refresh before continuing.");
    }
    if (previous && !transition &&
        (["submitted", "approved"].includes(priorStatus) || (!input.draft && priorStatus !== "published"))) {
      throw new AccountInputError("Wait for the current plan decision before editing.");
    }
    const version = transition ? priorVersion : previous ? priorVersion + 1 : 1;
    const versionRef = ref.collection("versions").doc(String(version));
    const scopedActor = { ...actor, displayName: account.full_name || actor.displayName || actor.uid };
    const auditPlan = (event: Parameters<FirestoreAuditWriter["appendInTransaction"]>[1]["action"], status: string) =>
      audit.appendInTransaction(transaction, { actor: scopedActor, action: event, targetType: "plan",
        targetId: ref.id, clientId, dietitianId: assignment.team.dietitianId, version, status,
        outcome: "succeeded", correlationId });
    const status = transition?.to ?? (input.draft ? "draft" : "published");
    const content = {
      title: transition ? previous!.title : title,
      description: transition ? previous!.description : description,
      dietitian_name: transition ? previous!.dietitian_name : account.full_name,
      status, version,
    };
    const updatedAt = FieldValue.serverTimestamp();
    const published = status === "published" ? content : previous?.published ??
      (previous && priorStatus === "published" ? { title: previous.title, description: previous.description,
        dietitian_name: previous.dietitian_name ?? "", status: "published", version: priorVersion } : undefined);
    const update = {
      ...content, client_id: clientId, assigned_by_id: assignment.team.dietitianId, assigned_by_role: "dietitian",
      updated_at: updatedAt, return_reason: action === "return" ? reason : null,
      ...(published ? { published } : {}),
      ...(status === "published" ? { published_at: updatedAt } : {}),
    };
    if (current.exists) transaction.update(ref, update);
    else transaction.create(ref, { ...update, created_at: updatedAt });
    if (transition) transaction.update(versionRef, { status, return_reason: update.return_reason, updated_at: updatedAt });
    else transaction.create(versionRef, { ...content, client_id: clientId, plan_id: ref.id,
      dietitian_id: assignment.team.dietitianId, created_at: updatedAt });
    if (!transition) auditPlan(current.exists ? "plan.revised" : "plan.created", status);
    else if (transition.event !== "plan.published") auditPlan(transition.event, status);
    if (status === "published") audit.appendWithEvent(transaction, {
      actor: scopedActor, action: "plan.published", targetType: "plan", targetId: ref.id, clientId,
      dietitianId: assignment.team.dietitianId, version, status, outcome: "succeeded", correlationId,
      operationId: `published-v${version}`,
    }, "plan.published");
  });
  return publicDietPlan(ref.id, (await ref.get()).data()!, false);
}
