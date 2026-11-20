import { createHmac, randomInt, randomUUID, timingSafeEqual } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";

export interface EmailIdentity {
  uid: string;
  email: string;
  emailVerified: boolean;
}

export interface EmailCodeRecord {
  email: string;
  nonce: string;
  digest: string;
  expiresAt: number;
  resendAt: number;
  windowStart: number;
  sends: number;
  attempts: number;
  status: "sending" | "sent" | "failed" | "verifying" | "consumed";
}

export interface EmailCodeStore {
  // Updates and reads must be atomic across all server instances.
  mutate<T>(
    uid: string,
    change: (record: EmailCodeRecord | undefined) => {
      record: EmailCodeRecord | undefined;
      value: T;
    },
  ): Promise<T>;
}

export class SignupEmailCodeService {
  constructor(
    private readonly store: EmailCodeStore,
    private readonly mailer: (email: string, code: string) => Promise<void>,
    private readonly markVerified: (identity: EmailIdentity) => Promise<void>,
    private readonly hashSecret: string,
    private readonly now: () => number = Date.now,
  ) {
    if (hashSecret.length < 32) {
      throw new HttpsError("failed-precondition", "Email verification is not configured.");
    }
  }

  async send(identity: EmailIdentity, options: { resend?: boolean } = {}): Promise<{ resendAfterSeconds: number }> {
    if (identity.emailVerified) {
      throw new HttpsError("failed-precondition", "This email is already verified.");
    }
    const now = this.now();
    const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
    const nonce = randomUUID();
    const shouldSend = await this.store.mutate(identity.uid, (previous) => {
      // A resumed signup uses the existing valid code. Only an explicit resend
      // replaces it; reopening the app must not invalidate the email in flight.
      if (!options.resend && previous?.email === identity.email &&
          previous.status === "sent" && now < previous.expiresAt) {
        return { record: previous, value: false };
      }
      if (previous && now < previous.resendAt) {
        throw new HttpsError("resource-exhausted", "Wait before requesting another code.", {
          reason: "resend-cooldown",
          retryAfterSeconds: Math.ceil((previous.resendAt - now) / 1000),
        });
      }
      const sameWindow = previous && now - previous.windowStart < 3_600_000;
      const sends = sameWindow ? previous.sends : 0;
      if (sends >= 5) {
        throw new HttpsError("resource-exhausted", "Too many code requests. Try later.", {
          reason: "send-limit",
          retryAfterSeconds: Math.ceil((previous!.windowStart + 3_600_000 - now) / 1000),
        });
      }
      return {
        record: {
          email: identity.email,
          nonce,
          digest: this.digest(identity, nonce, code),
          expiresAt: now + 600_000,
          resendAt: now + 60_000,
          windowStart: sameWindow ? previous.windowStart : now,
          sends: sends + 1,
          attempts: 0,
          status: "sending",
        },
        value: true,
      };
    });

    if (!shouldSend) {
      return this.store.mutate(identity.uid, record => ({ record,
        value: { resendAfterSeconds: Math.max(0, Math.ceil(((record?.resendAt ?? now) - now) / 1000)) } }));
    }

    try {
      await this.mailer(identity.email, code);
      await this.store.mutate(identity.uid, (record) => ({
        record: record?.nonce === nonce ? { ...record, status: "sent" } : record,
        value: undefined,
      }));
    } catch (_) {
      await this.store.mutate(identity.uid, (record) => ({
        record: record?.nonce === nonce
          ? { ...record, digest: "", status: "failed" }
          : record,
        value: undefined,
      }));
      throw new HttpsError("unavailable", "We could not send the verification code.");
    }
    return { resendAfterSeconds: 60 };
  }

  async verify(identity: EmailIdentity, code: unknown): Promise<{ verified: true }> {
    if (typeof code !== "string" || !/^\d{6}$/.test(code)) {
      throw new HttpsError("invalid-argument", "Enter a six-digit code.");
    }
    // Allows retry after the Admin update succeeded but the response was lost.
    if (identity.emailVerified) return { verified: true };
    const result = await this.store.mutate(identity.uid, (record) => {
      if (record?.status === "verifying" && record.email === identity.email) {
        return { record, value: { outcome: "busy", nonce: record.nonce } };
      }
      if (!record || record.email !== identity.email || record.status !== "sent") {
        return { record, value: { outcome: "missing", nonce: "" } };
      }
      if (this.now() >= record.expiresAt) return { record, value: { outcome: "expired", nonce: record.nonce } };
      if (record.attempts >= 5) return { record, value: { outcome: "exhausted", nonce: record.nonce } };
      const expected = Buffer.from(record.digest, "hex");
      const supplied = Buffer.from(this.digest(identity, record.nonce, code), "hex");
      const matches = expected.length === supplied.length &&
        timingSafeEqual(expected, supplied);
      // Return a failure instead of throwing inside the transaction, so failed
      // attempts are committed and cannot be bypassed by concurrent requests.
      return {
        record: { ...record, attempts: record.attempts + (matches ? 0 : 1),
          ...(matches ? { status: "verifying" as const } : {}) },
        value: { outcome: matches ? "verified" : "incorrect", nonce: record.nonce },
      };
    });
    if (result.outcome === "expired") throw new HttpsError("deadline-exceeded", "The code expired.");
    if (result.outcome === "exhausted") throw new HttpsError("resource-exhausted", "Request a new code.", {
      reason: "attempt-limit",
    });
    if (result.outcome === "busy") throw new HttpsError("unavailable", "Verification is in progress. Please try again.");
    if (result.outcome !== "verified") throw new HttpsError("invalid-argument", "The code is invalid.");
    try {
      await this.markVerified(identity);
    } catch (_) {
      // An Admin/network failure does not consume a correct code or count as a
      // wrong attempt. A retry can finish the same verified-email update.
      await this.store.mutate(identity.uid, record => ({
        record: record?.nonce === result.nonce && record.status === "verifying"
          ? { ...record, status: "sent" } : record,
        value: undefined,
      }));
      throw new HttpsError("unavailable", "We could not finish email verification. Please try again.");
    }
    await this.store.mutate(identity.uid, record => ({
      record: record?.nonce === result.nonce
        ? { ...record, status: "consumed", digest: "" } : record,
      value: undefined,
    }));
    return { verified: true };
  }

  private digest(identity: EmailIdentity, nonce: string, code: string): string {
    return createHmac("sha256", this.hashSecret)
      .update(JSON.stringify([identity.uid, identity.email, nonce, code]))
      .digest("hex");
  }
}
