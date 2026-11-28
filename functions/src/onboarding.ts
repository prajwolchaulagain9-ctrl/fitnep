import { FieldValue, Firestore } from "firebase-admin/firestore";
import { AccountInputError, accountFrom, accountMatchesActor } from "./account_service";
import { PermissionDeniedError } from "./authorization_policy";
import { isObject } from "./client_intake_answers";
import { AuthenticatedUser } from "./domain";

interface Onboarding {
  status: "required" | "draft" | "skipped" | "completed";
  heightCm?: number;
  weightKg?: number;
  bmi?: number;
}

export function onboarding(data: unknown): Onboarding {
  if (isObject(data) && (data.status === "draft" || data.status === "completed" || data.status === "skipped")) {
    return {
      status: data.status,
      ...(valid(data.heightCm, 30, 300) ? { heightCm: data.heightCm } : {}),
      ...(valid(data.weightKg, 1, 500) ? { weightKg: data.weightKg } : {}),
      ...(typeof data.bmi === "number" && data.status === "completed" ? { bmi: data.bmi } : {}),
    };
  }
  return { status: "required" };
}

export function onboardingReady(data: unknown): boolean {
  const status = onboarding(data).status;
  return status === "completed" || status === "skipped";
}

export async function saveOnboarding(db: Firestore, actor: AuthenticatedUser, input: Record<string, unknown>) {
  if (actor.role !== "client" || actor.emailVerified === false ||
      (input.expected_client_id !== undefined && input.expected_client_id !== actor.uid)) throw new PermissionDeniedError();
  const { status, heightCm, weightKg } = input;
  if (Object.keys(input).some(key => !["status", "heightCm", "weightKg", "expected_client_id"].includes(key)) ||
      (status !== "draft" && status !== "skipped" && status !== "completed") ||
      (heightCm !== undefined && !valid(heightCm, 30, 300)) ||
      (weightKg !== undefined && !valid(weightKg, 1, 500))) {
    throw new AccountInputError("Enter height from 30 to 300 cm and weight from 1 to 500 kg.");
  }
  return db.runTransaction(async tx => {
    const ref = db.doc(`users/${actor.uid}`);
    const data = (await tx.get(ref)).data();
    if (!accountMatchesActor(accountFrom(actor.uid, data), actor)) throw new PermissionDeniedError();
    const current = onboarding(data?.onboarding);
    if (current.status === "completed" && status !== "completed") return current;
    const next: Onboarding = { status: current.status === "skipped" && status === "draft" ? "skipped" : status };
    const height = heightCm ?? current.heightCm;
    const weight = weightKg ?? current.weightKg;
    if (valid(height, 30, 300)) next.heightCm = height;
    if (valid(weight, 1, 500)) next.weightKg = weight;
    if (status === "completed") {
      if (next.heightCm === undefined || next.weightKg === undefined) {
        throw new AccountInputError("Enter height and weight to complete onboarding.");
      }
      next.bmi = Math.round(10 * next.weightKg / (next.heightCm / 100) ** 2) / 10;
    }
    tx.update(ref, { onboarding: next, updated_at: FieldValue.serverTimestamp() });
    return next;
  });
}

function valid(value: unknown, min: number, max: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= min && value <= max;
}
