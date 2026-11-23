import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  FirestorePrivacyAcceptanceStore,
  PrivacyAcceptanceError,
  requiresClientPrivacyAcceptance,
} from "./privacy_policy_acceptance";

const { requireValidSession } = require("../src/session.cjs");

export const registrationPrivacy = onCall({ region: "us-central1" }, async (request) => {
  const token = await requireValidSession(request);
  const data = request.data;
  // A session change while a form is open must never record consent for the next user.
  if (data?.uid !== token.uid) throw new HttpsError("failed-precondition", "Account changed.");
  if (!requiresClientPrivacyAcceptance(token.role)) return { accepted: true };
  if (token.email_verified !== true) {
    throw new HttpsError("failed-precondition", "Verify your email before recording privacy consent.");
  }
  const store = new FirestorePrivacyAcceptanceStore(getFirestore());
  if (data.action === "status") return { accepted: await store.hasCurrentAcceptance(token.uid) };
  if (data.action !== "accept") throw new HttpsError("invalid-argument", "Unknown action.");
  try {
    await store.recordForClient(token.uid, data);
  } catch (error) {
    if (error instanceof PrivacyAcceptanceError) throw new HttpsError("invalid-argument", error.message);
    throw error;
  }
  return { accepted: true };
});
