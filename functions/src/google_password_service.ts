import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { Auth } from "firebase-admin/auth";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { AuthenticatedUser } from "./domain";
import { BrevoMailer } from "./brevo_mailer";

interface Setup {
  email: string;
  operationId: string;
  previousOperationId?: string;
  expiresAt: number;
  leaseUntil: number;
  status: "pending" | "installed" | "sent" | "completed";
  ciphertext?: string;
  iv?: string;
  tag?: string;
  digest: string;
  keyId: string;
}

// Passwords are encrypted only while mail is pending, then removed from storage.
// Both installation and retry belong to a recent, verified Google sign-in.
export class GooglePasswordService {
  constructor(private readonly auth: Auth, private readonly db: Firestore,
    private readonly mailer: BrevoMailer, private readonly secret: string,
    private readonly now = Date.now) {}

  async send(actor: AuthenticatedUser) {
    if (actor.signInProvider !== "google.com" || actor.emailVerified !== true ||
        !actor.authTime || this.now() / 1000 - actor.authTime > 300) {
      throw new HttpsError("permission-denied", "Sign in with Google again to set up email login.");
    }
    const user = await this.auth.getUser(actor.uid);
    if (user.disabled || !user.emailVerified || !user.email || user.email !== actor.email ||
        !user.providerData.some(provider => provider.providerId === "google.com")) {
      throw new HttpsError("permission-denied", "This Google account cannot set up email login.");
    }
    const hasPassword = user.providerData.some(provider => provider.providerId === "password");
    const oldOperation = user.customClaims?.googlePasswordSetupId;
    if (hasPassword && typeof oldOperation !== "string") {
      return { email_sent: false, existing_password: true, credentials_updated: false };
    }
    this.mailer.assertConfigured();
    if (this.secret.length < 32) {
      throw new HttpsError("failed-precondition", "Email login setup is not configured.", { reason: "invalid-otp-secret" });
    }
    const reference = this.db.collection("google_password_setup").doc(actor.uid);
    const now = this.now();
    const reserved = await this.db.runTransaction(async transaction => {
      const previous = (await transaction.get(reference)).data() as Setup | undefined;
      if (previous && previous.email !== user.email) throw new HttpsError("failed-precondition", "The account email changed.");
      if (previous?.status === "sent") return { setup: previous, send: false };
      if (previous && previous.leaseUntil > now) {
        throw new HttpsError("resource-exhausted", "Email login setup is already in progress.");
      }
      let setup = previous;
      if (!setup || setup.expiresAt <= now || setup.status === "completed") {
        const password = `Fn!9aA${randomBytes(18).toString("base64url")}`;
        const operationId = randomUUID();
        const iv = randomBytes(12);
        const cipher = createCipheriv("aes-256-gcm", this.key(), iv);
        cipher.setAAD(Buffer.from(`${actor.uid}:${user.email}`));
        const ciphertext = Buffer.concat([cipher.update(password, "utf8"), cipher.final()]);
        setup = { email: user.email!, operationId, expiresAt: now + 86_400_000,
          leaseUntil: now + 120_000, status: "pending", ciphertext: ciphertext.toString("base64"),
          iv: iv.toString("base64"), tag: cipher.getAuthTag().toString("base64"),
          digest: this.digest(actor.uid, user.email!, password), keyId: this.keyId(),
          ...(typeof oldOperation === "string" ? { previousOperationId: oldOperation } : {}),
        };
      } else setup = { ...setup, leaseUntil: now + 120_000 };
      transaction.set(reference, setup);
      return { setup, send: true };
    });
    if (!reserved.send) return { email_sent: true, already_sent: true, credentials_updated: false };
    const setup = reserved.setup;
    let credentialsUpdated = false;
    try {
      const decipher = createDecipheriv("aes-256-gcm", this.key(), Buffer.from(setup.iv!, "base64"));
      decipher.setAAD(Buffer.from(`${actor.uid}:${setup.email}`));
      decipher.setAuthTag(Buffer.from(setup.tag!, "base64"));
      const password = Buffer.concat([decipher.update(Buffer.from(setup.ciphertext!, "base64")), decipher.final()]).toString("utf8");
      if (setup.status === "pending") {
        const latest = await this.auth.getUser(actor.uid);
        if (latest.disabled || latest.email !== setup.email || !latest.emailVerified) throw new HttpsError("permission-denied", "The account changed.");
        if (latest.providerData.some(provider => provider.providerId === "password") &&
            latest.customClaims?.googlePasswordSetupId !== setup.operationId &&
            !(typeof setup.previousOperationId === "string" && latest.customClaims?.googlePasswordSetupId === setup.previousOperationId)) {
          throw new HttpsError("failed-precondition", "This account already has its own password.");
        }
        await this.auth.setCustomUserClaims(actor.uid, { ...latest.customClaims,
          googlePasswordSetupId: setup.operationId, googleTemporaryPasswordUntil: setup.expiresAt });
        await this.auth.updateUser(actor.uid, { password });
        credentialsUpdated = true;
        await reference.update({ status: "installed" });
      }
      const messageId = await this.mailer.send(setup.email, "Your FitNEP temporary password",
        `You created your FitNEP account with Google.\n\nEmail: ${setup.email}\nTemporary password: ${password}\n\n` +
        "You can log in with this email and password. It expires in 24 hours; choose your own password at your first email login. " +
        "Google sign-in continues to work. If you did not request this, contact FitNEP support.");
      await reference.update({ status: "sent", leaseUntil: 0, message_id: messageId,
        sent_at: FieldValue.serverTimestamp(), ciphertext: FieldValue.delete(), iv: FieldValue.delete(), tag: FieldValue.delete() });
      return { email_sent: true, credentials_updated: credentialsUpdated };
    } catch (error) {
      await reference.update({ leaseUntil: 0 }).catch(() => undefined);
      throw new HttpsError(error instanceof HttpsError ? error.code : "unavailable",
        "Could not finish temporary-password email delivery.", {
          ...(error instanceof HttpsError && error.details && typeof error.details === "object" ? error.details : {}),
          credentials_updated: credentialsUpdated,
        });
    }
  }

  async change(actor: AuthenticatedUser, password: unknown) {
    if (this.secret.length < 32) throw new HttpsError("failed-precondition", "Password setup is not configured.");
    const googleRecovery = actor.signInProvider === "google.com" && actor.emailVerified === true &&
      !!actor.authTime && this.now() / 1000 - actor.authTime <= 300;
    if (actor.googleTemporaryPassword !== true || (!googleRecovery && (!actor.passwordAuthenticatedAt ||
        this.now() / 1000 - actor.passwordAuthenticatedAt > 300))) {
      throw new HttpsError("permission-denied", "Sign in with your temporary password again.");
    }
    if (typeof password !== "string" || password.trim().length < 8 || Buffer.byteLength(password, "utf8") > 128) {
      throw new HttpsError("invalid-argument", "Use a password of at least 8 characters and at most 128 bytes.");
    }
    const user = await this.auth.getUser(actor.uid);
    const reference = this.db.collection("google_password_setup").doc(actor.uid);
    const setup = (await reference.get()).data() as Setup | undefined;
    if (setup && setup.keyId !== this.keyId()) throw new HttpsError("failed-precondition", "Password setup configuration changed. Contact support.");
    if (user.disabled || !setup || setup.email !== user.email || setup.operationId !== user.customClaims?.googlePasswordSetupId ||
        (!googleRecovery && setup.expiresAt <= this.now())) {
      throw new HttpsError("failed-precondition", "Your temporary password expired. Sign in with Google to choose a new password.");
    }
    const expected = Buffer.from(setup.digest, "hex");
    const supplied = Buffer.from(this.digest(actor.uid, setup.email, password), "hex");
    if (expected.length === supplied.length && timingSafeEqual(expected, supplied)) {
      throw new HttpsError("invalid-argument", "Choose a different password.");
    }
    await this.auth.updateUser(actor.uid, { password });
    const claims = { ...user.customClaims };
    delete claims.googlePasswordSetupId;
    delete claims.googleTemporaryPasswordUntil;
    await this.auth.setCustomUserClaims(actor.uid, claims);
    await this.auth.revokeRefreshTokens(actor.uid);
    await reference.update({ status: "completed", digest: "", completed_at: FieldValue.serverTimestamp() });
  }

  private key() { return createHash("sha256").update(`fitnep-google-password-v1:${this.secret}`).digest(); }
  private keyId() { return createHash("sha256").update(this.secret).digest("hex").slice(0, 16); }
  private digest(uid: string, email: string, password: string) {
    return createHmac("sha256", this.secret).update(JSON.stringify(["google-password", uid, email, password])).digest("hex");
  }
}
