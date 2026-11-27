import express from "express";
import { Auth } from "firebase-admin/auth";
import { Firestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { AuthVerifier, AuthenticationError } from "./auth";
import { FirestoreAuditStore } from "./account_service";
import { EmailCodeRecord, EmailCodeStore, SignupEmailCodeService } from "./signup_email_code_service";
import { FirestorePrivacyAcceptanceStore, PrivacyAcceptanceError } from "./privacy_policy_acceptance";
import { BrevoMailer } from "./brevo_mailer";
import { GooglePasswordService } from "./google_password_service";

// The existing Firebase SDK remains the credential authority. This adapter
// hosts the application prerequisites without requiring Firebase Functions.
export function mountHostedAuth(auth: Auth, firestore: Firestore, verifier: AuthVerifier,
  environment: NodeJS.ProcessEnv, transport: typeof fetch = fetch): express.Express {
  const app = express();
  app.disable("x-powered-by");
  app.use("/auth", express.json({ limit: "8kb" }));
  app.use((_request, response, next) => { response.set("Cache-Control", "no-store"); next(); });
  const privacy = new FirestorePrivacyAcceptanceStore(firestore);
  const mailer = new BrevoMailer(environment, transport);
  const googlePasswords = new GooglePasswordService(auth, firestore, mailer, environment.SIGNUP_OTP_HASH_SECRET || "");
  const protectedRoute = (path: string, action: (uid: string, body: Record<string, unknown>, response: express.Response) => Promise<void>) => {
    app.post(path, (request, response, next) => {
      void (async () => {
        const token = request.header("Authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
        if (!token) throw new AuthenticationError("Sign in to continue.");
        const actor = await verifier.verifyIdToken(token);
        response.locals.actor = actor;
        if (actor.mustChangePassword) throw new AuthenticationError("Complete password setup first.", 403);
        if (!request.body || typeof request.body !== "object" || Array.isArray(request.body) || Object.keys(request.query).length) {
          throw new HttpsError("invalid-argument", "Invalid request.");
        }
        await action(actor.uid, request.body, response);
      })().catch(next);
    });
  };
  const identity = async (uid: string) => {
    const user = await auth.getUser(uid);
    if (user.disabled || !user.email || !user.providerData.some(provider => provider.providerId === "password")) {
      throw new HttpsError("failed-precondition", "An email/password account is required.");
    }
    return { uid, email: user.email, emailVerified: user.emailVerified };
  };
  const codes = () => {
    const secret = environment.SIGNUP_OTP_HASH_SECRET;
    if (environment.SIGNUP_EMAIL_OTP_ENABLED?.trim().toLowerCase() === "false" || !secret || secret.length < 32) {
      throw new HttpsError("failed-precondition", "Email verification is not configured.", {
        reason: !secret || secret.length < 32 ? "invalid-otp-secret" : "email-verification-disabled",
      });
    }
    mailer.assertConfigured();
    return new SignupEmailCodeService(new HostedEmailCodeStore(firestore),
      (email, code) => mailer.send(email, "Verify your FitNEP email", `Your FitNEP verification code is ${code}. It expires in 10 minutes. If you did not request this, ignore this email.`), async proven => {
      const latest = await auth.getUser(proven.uid);
      if (latest.disabled || latest.email !== proven.email) throw new HttpsError("failed-precondition", "Account changed.");
      await auth.updateUser(proven.uid, { email: proven.email, emailVerified: true });
    }, secret);
  };
  protectedRoute("/auth/google/email-password", async (_uid, body, response) => {
    if (Object.keys(body).length) throw new HttpsError("invalid-argument", "No account details are accepted.");
    response.json({ data: await googlePasswords.send(response.locals.actor) });
  });
  protectedRoute("/auth/signup/otp/send", async (uid, body, response) => {
    if (Object.keys(body).some(key => key !== "resend") || (body.resend !== undefined && typeof body.resend !== "boolean")) {
      throw new HttpsError("invalid-argument", "Supply only a resend flag.");
    }
    const user = await identity(uid);
    response.json({ data: user.emailVerified ? { emailVerified: true, resendAfterSeconds: 0 }
      : await codes().send(user, { resend: body.resend === true }) });
  });
  protectedRoute("/auth/signup/otp/verify", async (uid, body, response) => {
    if (Object.keys(body).some(key => key !== "code")) throw new HttpsError("invalid-argument", "Supply only a code.");
    response.json({ data: await codes().verify(await identity(uid), body.code) });
  });
  protectedRoute("/auth/privacy", async (uid, body, response) => {
    if (body.uid !== uid) throw new AuthenticationError("Account changed.", 403);
    if (response.locals.actor.role !== "client") { response.json({ data: { accepted: true } }); return; }
    if (!response.locals.actor.emailVerified) throw new AuthenticationError("Verify your email before continuing.", 403);
    if (body.action === "status") { response.json({ data: { accepted: await privacy.hasCurrentAcceptance(uid) } }); return; }
    if (body.action !== "accept" || Object.keys(body).some(key => !["action", "uid", "age", "privacy_policy_version", "privacy_policy_accepted", "guardian_consent_confirmed", "terms_accepted", "terms_version"].includes(key))) {
      throw new HttpsError("invalid-argument", "Invalid consent request.");
    }
    await privacy.recordForClient(uid, body);
    response.json({ data: { accepted: true } });
  });
  // Reset codes remain Firebase-issued, expiring and single-use. The public web
  // API key identifies the Firebase project; it grants no Admin permissions.
  for (const action of ["request", "verify", "confirm"] as const) {
    app.post("/auth/recovery/" + action, (request, response, next) => {
      void (async () => {
        const key = environment.FIREBASE_WEB_API_KEY;
        if (!key) throw new HttpsError("failed-precondition", "Recovery is not configured.");
        const body = request.body;
        const allowed = action === "request" ? ["email"] : action === "verify" ? ["code"] : ["code", "password"];
        if (!body || Array.isArray(body) || Object.keys(body).some(field => !allowed.includes(field)) ||
            allowed.some(field => typeof body[field] !== "string" || body[field].length < 1 || body[field].length > 2048) || Object.keys(request.query).length) {
          throw new HttpsError("invalid-argument", "Invalid recovery request.");
        }
        if (action === "request" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(body.email)) throw new HttpsError("invalid-argument", "Enter a valid email.");
        const method = action === "request" ? "sendOobCode" : "resetPassword";
        const result = await transport(`https://identitytoolkit.googleapis.com/v1/accounts:${method}?key=${encodeURIComponent(key)}`, {
          method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify(action === "request" ? { requestType: "PASSWORD_RESET", email: body.email }
            : { oobCode: body.code, ...(action === "confirm" ? { newPassword: body.password } : {}) }),
          signal: AbortSignal.timeout(15_000),
        });
        const data = await result.json() as { email?: string; error?: { message?: string } };
        const code = data.error?.message?.split(" : ")[0];
        if (action === "request" && (result.ok || ["EMAIL_NOT_FOUND", "USER_DISABLED"].includes(code ?? ""))) {
          response.json({ data: { requested: true } }); return;
        }
        if (!result.ok) {
          throw new HttpsError(code === "TOO_MANY_ATTEMPTS_TRY_LATER" ? "resource-exhausted"
            : ["INVALID_OOB_CODE", "EXPIRED_OOB_CODE"].includes(code ?? "") ? "not-found"
            : code?.startsWith("WEAK_PASSWORD") ? "invalid-argument" : "unavailable", "Recovery could not be completed.");
        }
        response.json({ data: action === "verify" ? { email: data.email } : { confirmed: true } });
      })().catch(next);
    });
  }
  app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
    if (error instanceof Error && "type" in error &&
        (error.type === "entity.too.large" || error.type === "entity.parse.failed")) {
      const tooLarge = error.type === "entity.too.large";
      response.status(tooLarge ? 413 : 400).json({
        code: "invalid-argument", error: tooLarge ? "The submitted data is too large." : "Invalid request body.",
      });
      return;
    }
    const actor = response.locals.actor;
    const denied = (error instanceof AuthenticationError && error.statusCode === 403) ||
      (error instanceof HttpsError && error.code === "permission-denied");
    const finish = () => {
      const status = error instanceof AuthenticationError ? error.statusCode : error instanceof PrivacyAcceptanceError ? 400
        : error instanceof HttpsError ? ({ "invalid-argument": 400, "not-found": 404, "deadline-exceeded": 410,
            "resource-exhausted": 429, "failed-precondition": 503 } as Record<string, number>)[error.code] ?? error.httpErrorCode.status : 503;
      response.status(status).json({ code: denied ? "permission-denied" : error instanceof HttpsError ? error.code : status === 401 ? "unauthenticated" : "unavailable",
        error: denied ? "You do not have permission to access this feature." : "The account request could not be completed. Please try again.",
        ...(error instanceof HttpsError && error.details ? { details: error.details } : {}) });
    };
    if (denied && actor) {
      void new FirestoreAuditStore(firestore).denied({ uid: actor.uid, role: actor.role,
        action: "account_prerequisite", resource: "hosted_auth", reason: "Authorization denied." }).then(finish,
          () => { response.status(503).json({ code: "unavailable", error: "Account services are unavailable." }); });
    } else finish();
  });
  return app;
}

class HostedEmailCodeStore implements EmailCodeStore {
  constructor(private readonly firestore: Firestore) {}
  mutate<T>(uid: string, change: (record: EmailCodeRecord | undefined) => { record: EmailCodeRecord | undefined; value: T }): Promise<T> {
    return this.firestore.runTransaction(async transaction => {
      const reference = this.firestore.collection("signup_email_codes").doc(uid);
      const snapshot = await transaction.get(reference);
      const { record, value } = change(snapshot.data() as EmailCodeRecord | undefined);
      if (record) transaction.set(reference, { ...record, expires_at: Timestamp.fromMillis(Math.max(record.expiresAt, record.windowStart + 3_600_000)) });
      return value;
    });
  }
}
