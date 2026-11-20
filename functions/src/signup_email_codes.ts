import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { defineBoolean, defineSecret, defineString } from "firebase-functions/params";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

import { EmailCodeRecord, EmailCodeStore, EmailIdentity, SignupEmailCodeService } from "./signup_email_code_service";

// CommonJS recovery helpers stay in src; TypeScript deploys from lib.
const { requireValidSession } = require("../src/session.cjs");
const brevoApiKey = defineSecret("BREVO_API_KEY");
const otpHashSecret = defineSecret("SIGNUP_OTP_HASH_SECRET");
const enabled = defineBoolean("SIGNUP_EMAIL_OTP_ENABLED", { default: true });
const senderEmail = defineString("BREVO_SENDER_EMAIL", { default: "" });
const senderName = defineString("BREVO_SENDER_NAME", { default: "FitNEP" });

class FirestoreEmailCodeStore implements EmailCodeStore {
  async mutate<T>(uid: string, change: (record: EmailCodeRecord | undefined) => {
    record: EmailCodeRecord | undefined;
    value: T;
  }): Promise<T> {
    const firestore = getFirestore();
    const document = firestore.collection("signup_email_codes").doc(uid);
    return firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(document);
      const { record, value } = change(snapshot.data() as EmailCodeRecord | undefined);
      if (record) {
        // Retain the rate-limit window even after the OTP itself has expired.
        transaction.set(document, {
          ...record,
          expires_at: Timestamp.fromMillis(Math.max(record.expiresAt, record.windowStart + 3_600_000)),
        });
      }
      return value;
    });
  }
}

async function identityFor(request: CallableRequest): Promise<EmailIdentity> {
  if (!enabled.value()) {
    throw new HttpsError("failed-precondition", "Email verification is not enabled.");
  }
  // Verify revocation using the actual bearer token, not client-supplied UID/email.
  const token = await requireValidSession(request);
  const user = await getAuth().getUser(token.uid);
  if (user.disabled || !user.email ||
      !user.providerData.some((provider) => provider.providerId === "password")) {
    throw new HttpsError("failed-precondition", "An email/password account is required.");
  }
  return { uid: user.uid, email: user.email, emailVerified: user.emailVerified };
}

function createService(): SignupEmailCodeService {
  if (!brevoApiKey.value() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(senderEmail.value())) {
    throw new HttpsError("failed-precondition", "Email verification is not configured.");
  }
  return new SignupEmailCodeService(
    new FirestoreEmailCodeStore(),
    async (email, code) => {
      // Brevo credentials and verification codes stay on the server. Never log
      // the request/response body: it may contain account data or the OTP.
      const response = await fetch("https://api.brevo.com/v3/smtp/email", {
        method: "POST",
        headers: { "api-key": brevoApiKey.value(), "Content-Type": "application/json" },
        body: JSON.stringify({
          sender: { email: senderEmail.value(), name: senderName.value() },
          to: [{ email }],
          subject: "Verify your FitNEP email",
          textContent: `Your FitNEP verification code is ${code}. It expires in 10 minutes. If you did not request this, ignore this email.`,
        }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) throw new Error("Email delivery failed.");
    },
    async (identity) => {
      const latest = await getAuth().getUser(identity.uid);
      if (latest.disabled || latest.email !== identity.email) {
        throw new HttpsError("failed-precondition", "The account email has changed.");
      }
      // Pin the proven email in the same update as its verification flag.
      await getAuth().updateUser(identity.uid, { email: identity.email, emailVerified: true });
    },
    otpHashSecret.value(),
  );
}

const options = {
  region: "us-central1",
  timeoutSeconds: 30,
  maxInstances: 5,
  secrets: [brevoApiKey, otpHashSecret],
};

export const sendSignupEmailCode = onCall(options, async (request) => {
  const identity = await identityFor(request);
  if (identity.emailVerified) return { emailVerified: true, resendAfterSeconds: 0 };
  return createService().send(identity, { resend: request.data?.resend === true });
});

export const verifySignupEmailCode = onCall(options, async (request) => {
  const identity = await identityFor(request);
  return createService().verify(identity, request.data?.code);
});
