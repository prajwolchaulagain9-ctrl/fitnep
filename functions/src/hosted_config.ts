import { ServiceAccount } from "firebase-admin/app";

export interface HostedConfig {
  projectId: string;
  port: number;
  buildSha: string;
  idleTimeoutSeconds: number;
  serviceAccount?: ServiceAccount;
}

export class HostedConfigurationError extends Error {}

export function readHostedConfig(environment: NodeJS.ProcessEnv): HostedConfig {
  if (environment.FIREBASE_AUTH_EMULATOR_HOST || environment.FIRESTORE_EMULATOR_HOST ||
    environment.FIREBASE_DATABASE_EMULATOR_HOST) {
    throw new HostedConfigurationError("The hosted API cannot use Firebase emulators.");
  }
  const projectId = environment.FIREBASE_PROJECT_ID?.trim();
  if (!projectId || !/^[a-z][a-z0-9-]{4,62}$/.test(projectId) || projectId.startsWith("demo-")) {
    throw new HostedConfigurationError("Set FIREBASE_PROJECT_ID to the owned cloud project.");
  }
  const port = positiveInteger(environment.PORT ?? "3000", 65535);
  const idleTimeoutSeconds = positiveInteger(environment.SESSION_IDLE_TIMEOUT_SECONDS ?? "900", 86400);
  const buildSha = environment.FITNEP_BUILD_SHA ?? environment.RENDER_GIT_COMMIT ?? "unknown";
  if (!/^[a-f0-9]{40}$/i.test(buildSha)) {
    throw new HostedConfigurationError("Set FITNEP_BUILD_SHA or RENDER_GIT_COMMIT to the deployed commit SHA.");
  }
  let serviceAccount: ServiceAccount | undefined;
  if (environment.FIREBASE_SERVICE_ACCOUNT_JSON) {
    let input: Record<string, unknown>;
    try {
      input = JSON.parse(environment.FIREBASE_SERVICE_ACCOUNT_JSON);
      if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error();
    } catch {
      throw new HostedConfigurationError("FIREBASE_SERVICE_ACCOUNT_JSON must be valid service-account JSON.");
    }
    if (input.project_id !== projectId || typeof input.client_email !== "string" ||
      !input.client_email.endsWith(".iam.gserviceaccount.com") ||
      typeof input.private_key !== "string" || !input.private_key.includes("BEGIN PRIVATE KEY")) {
      throw new HostedConfigurationError("The Firebase service account must belong to FIREBASE_PROJECT_ID.");
    }
    serviceAccount = { projectId, clientEmail: input.client_email, privateKey: input.private_key };
  } else if (!environment.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new HostedConfigurationError("Configure FIREBASE_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS on the host.");
  }
  return { projectId, port, buildSha, idleTimeoutSeconds, ...(serviceAccount ? { serviceAccount } : {}) };
}

function positiveInteger(value: string, maximum: number): number {
  if (!/^[1-9][0-9]*$/.test(value) || Number(value) > maximum) {
    throw new HostedConfigurationError("PORT and SESSION_IDLE_TIMEOUT_SECONDS must be positive integers within their limits.");
  }
  return Number(value);
}
