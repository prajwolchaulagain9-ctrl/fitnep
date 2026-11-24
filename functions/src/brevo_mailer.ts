import { HttpsError } from "firebase-functions/v2/https";

export class BrevoMailer {
  constructor(private readonly environment: NodeJS.ProcessEnv, private readonly transport: typeof fetch = fetch) {}

  assertConfigured() {
    if (!this.environment.BREVO_API_KEY || !this.environment.BREVO_SENDER_EMAIL ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.environment.BREVO_SENDER_EMAIL)) {
      throw new HttpsError("failed-precondition", "Email delivery is not configured.", { reason: "email-configuration" });
    }
  }

  async send(email: string, subject: string, textContent: string): Promise<string> {
    this.assertConfigured();
    const response = await this.transport("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": this.environment.BREVO_API_KEY!, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        sender: { email: this.environment.BREVO_SENDER_EMAIL, name: this.environment.BREVO_SENDER_NAME || "FitNEP" },
        to: [{ email }], subject, textContent,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      throw new HttpsError(response.status === 401 || response.status === 403 ? "failed-precondition" : "unavailable",
        "Email delivery could not be completed.", {
          reason: response.status === 401 ? "email-provider-authentication" : "email-provider-rejection",
          providerStatus: response.status,
        });
    }
    const body = await response.json() as { messageId?: unknown };
    if (typeof body.messageId !== "string" || !body.messageId.trim()) {
      throw new HttpsError("unavailable", "Email delivery was not confirmed.");
    }
    return body.messageId;
  }
}
