import { FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { normalizeUserRole } from "./domain";

// Version 2 makes the explicitly assigned support team's access visible to clients.
export const privacyPolicyVersion = "2";

export function hasValidPrivacyAcceptance(data: Record<string, unknown> | undefined): boolean {
  return data?.policy_version === privacyPolicyVersion && data.accepted_at instanceof Timestamp &&
    typeof data.guardian_consent_confirmed === "boolean" &&
    (!data.guardian_consent_confirmed || data.guardian_consent_confirmed_at instanceof Timestamp);
}

export function requiresClientPrivacyAcceptance(roleClaim: unknown): boolean {
  const role = normalizeUserRole(roleClaim);
  return role === null || role === "client";
}

export interface RegistrationPrivacyInput {
  age?: unknown;
  privacy_policy_accepted?: unknown;
  privacy_policy_version?: unknown;
  guardian_consent_confirmed?: unknown;
  terms_accepted?: unknown;
  terms_version?: unknown;
}

export class PrivacyAcceptanceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PrivacyAcceptanceError";
  }
}

/** Validate the client's consent before completing registration. */
export function validatePrivacyAcceptance(input: RegistrationPrivacyInput) {
  const { age } = input;
  if (age !== undefined && (typeof age !== "number" || !Number.isInteger(age) || age < 1 || age > 120)) {
    throw new PrivacyAcceptanceError("Enter a valid age.");
  }
  if (input.privacy_policy_accepted !== true ||
      input.privacy_policy_version !== privacyPolicyVersion) {
    throw new PrivacyAcceptanceError(
      "Accept the current FitNEP Privacy Policy before registering.",
    );
  }
  if (age === undefined && (input.terms_accepted !== true || input.terms_version !== "1" ||
      input.guardian_consent_confirmed !== false)) {
    throw new PrivacyAcceptanceError("Accept the Terms and Conditions before registering.");
  }
  if (typeof age === "number" && age < 18 && input.guardian_consent_confirmed !== true) {
    throw new PrivacyAcceptanceError(
      "Confirm permission from a parent or guardian before registering.",
    );
  }
  return { age, guardianConsentConfirmed: typeof age === "number" && age < 18 };
}

export class FirestorePrivacyAcceptanceStore {
  constructor(private readonly firestore: Firestore) {}

  async hasCurrentAcceptance(uid: string, transaction?: Transaction): Promise<boolean> {
    const reference = this.firestore.collection("privacy_acceptances").doc(uid);
    const record = transaction ? await transaction.get(reference) : await reference.get();
    return hasValidPrivacyAcceptance(record.data());
  }

  /** Use the UID from the registration backend before activating the account. */
  async recordForClient(uid: string, input: RegistrationPrivacyInput): Promise<void> {
    const { age, guardianConsentConfirmed } = validatePrivacyAcceptance(input);
    const consent = this.firestore.collection("privacy_acceptances").doc(uid);
    await this.firestore.runTransaction(async (transaction) => {
      const current = await transaction.get(consent);
      const alreadyAccepted = hasValidPrivacyAcceptance(current.data());
      if (alreadyAccepted) return;

      transaction.set(consent, {
        policy_version: privacyPolicyVersion,
        accepted_at: FieldValue.serverTimestamp(),
        ...(age === undefined ? { onboarding_pending: true } : { age_at_acceptance: age }),
        ...(input.terms_accepted === true && input.terms_version === "1" ? {
          terms_version: "1", terms_accepted_at: FieldValue.serverTimestamp(),
        } : {}),
        guardian_consent_confirmed: guardianConsentConfirmed,
        ...(guardianConsentConfirmed ? {
          guardian_consent_confirmed_at: FieldValue.serverTimestamp(),
        } : {}),
      });
    });
  }
}
