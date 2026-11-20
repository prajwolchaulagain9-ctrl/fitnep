import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";

export const privacyPolicyVersion = "1";

export interface RegistrationPrivacyInput {
  age?: unknown;
  privacy_policy_accepted?: unknown;
  privacy_policy_version?: unknown;
  guardian_consent_confirmed?: unknown;
}

export class PrivacyAcceptanceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PrivacyAcceptanceError";
  }
}

/** Registration can call this before it creates an account. */
export function validatePrivacyAcceptance(input: RegistrationPrivacyInput) {
  const { age } = input;
  if (typeof age !== "number" || !Number.isInteger(age) || age < 1 || age > 120) {
    throw new PrivacyAcceptanceError("Enter a valid age.");
  }
  if (input.privacy_policy_accepted !== true ||
      input.privacy_policy_version !== privacyPolicyVersion) {
    throw new PrivacyAcceptanceError(
      "Accept the current FitNEP Privacy Policy before registering.",
    );
  }
  if (age < 18 && input.guardian_consent_confirmed !== true) {
    throw new PrivacyAcceptanceError(
      "Confirm permission from a parent or guardian before registering.",
    );
  }
  return { guardianConsentConfirmed: age < 18 };
}

export class FirestorePrivacyAcceptanceStore {
  constructor(private readonly firestore: Firestore) {}

  /** Use the UID from the registration backend before activating the account. */
  async recordForClient(uid: string, input: RegistrationPrivacyInput): Promise<void> {
    const { guardianConsentConfirmed } = validatePrivacyAcceptance(input);
    const consent = this.firestore.collection("privacy_acceptances").doc(uid);
    await this.firestore.runTransaction(async (transaction) => {
      const current = await transaction.get(consent);
      const alreadyAccepted = current.get("policy_version") === privacyPolicyVersion &&
        current.get("accepted_at") instanceof Timestamp;
      if (alreadyAccepted) return;

      transaction.set(consent, {
        policy_version: privacyPolicyVersion,
        accepted_at: FieldValue.serverTimestamp(),
        guardian_consent_confirmed: guardianConsentConfirmed,
        ...(guardianConsentConfirmed ? {
          guardian_consent_confirmed_at: FieldValue.serverTimestamp(),
        } : {}),
      });
    });
  }
}
