import assert from "node:assert/strict";
import { it } from "node:test";
import request from "supertest";

import { AuthenticationError } from "../src/auth";
import { HostedConfigurationError, readHostedConfig } from "../src/hosted_config";
import { createNotificationApp } from "../src/http_app";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

const environment = {
  FIREBASE_PROJECT_ID: "fitnep-owned",
  FITNEP_BUILD_SHA: "6f0c245a96be24dcc4e3247e46f5a6e4890b41f6",
  GOOGLE_APPLICATION_CREDENTIALS: "/etc/secrets/firebase-admin.json",
};

it("the standalone host uses the assigned port and a bounded configurable idle timeout", () => {
  const config = readHostedConfig({ ...environment, PORT: "10000" });
  assert.equal(config.projectId, "fitnep-owned");
  assert.equal(config.port, 10000);
  assert.equal(config.idleTimeoutSeconds, 900);
  assert.equal(readHostedConfig({ ...environment, SESSION_IDLE_TIMEOUT_SECONDS: "30" }).idleTimeoutSeconds, 30);
  assert.equal(readHostedConfig({
    ...environment, FITNEP_BUILD_SHA: undefined, RENDER_GIT_COMMIT: environment.FITNEP_BUILD_SHA,
  }).buildSha, environment.FITNEP_BUILD_SHA);
});

it("the hosted runner refuses emulators, missing credentials and invalid deployment settings", () => {
  for (const overrides of [
    { FIREBASE_AUTH_EMULATOR_HOST: "localhost:9099" },
    { FIRESTORE_EMULATOR_HOST: "localhost:18080" },
    { FIREBASE_PROJECT_ID: "demo-fitnep" },
    { GOOGLE_APPLICATION_CREDENTIALS: undefined },
    { FITNEP_BUILD_SHA: "unrecorded" },
    { PORT: "0" }, { PORT: "65536" }, { PORT: "3000.5" },
    { SESSION_IDLE_TIMEOUT_SECONDS: "-1" }, { SESSION_IDLE_TIMEOUT_SECONDS: "86401" },
  ]) {
    assert.throws(() => readHostedConfig({ ...environment, ...overrides }), HostedConfigurationError);
  }
});

it("malformed or wrong-project service-account JSON never appears in configuration errors", () => {
  for (const value of [
    "synthetic-sensitive-input", "null", "[]",
    JSON.stringify({ project_id: "different-project", private_key: "synthetic-sensitive-input" }),
  ]) {
    assert.throws(
      () => readHostedConfig({ ...environment, FIREBASE_SERVICE_ACCOUNT_JSON: value }),
      error => error instanceof HostedConfigurationError && !error.message.includes("synthetic-sensitive-input"),
    );
  }
});

it("health is public, identifies the build, and reports failed readiness without upstream details", async () => {
  let unavailable = false;
  const app = createNotificationApp({
    authVerifier: { verifyIdToken: async () => { throw new AuthenticationError("No identity."); } },
    notificationRepository: new InMemoryNotificationRepository(),
    health: {
      buildSha: environment.FITNEP_BUILD_SHA,
      checkReady: async () => { if (unavailable) throw new Error("synthetic-upstream-detail"); },
    },
  });
  const healthy = await request(app).get("/healthz").expect(200).expect("Cache-Control", "no-store");
  assert.equal(healthy.body.data.ready, true);
  assert.equal(healthy.body.data.build_sha, environment.FITNEP_BUILD_SHA);
  assert.equal(healthy.headers["x-powered-by"], undefined);
  await request(app).get("/packages").expect(401);
  unavailable = true;
  const failed = await request(app).get("/healthz").expect(503);
  assert.equal(failed.body.data.ready, false);
  assert(!JSON.stringify(failed.body).includes("synthetic-upstream-detail"));
});

it("an unknown build cannot pass the deployment health check", async () => {
  const app = createNotificationApp({
    authVerifier: { verifyIdToken: async () => assert.fail("health must not need a user") },
    notificationRepository: new InMemoryNotificationRepository(),
    health: { buildSha: "unknown", checkReady: async () => assert.fail("unknown build must fail first") },
  });
  const response = await request(app).get("/healthz").expect(503);
  assert.equal(response.body.data.ready, false);
});
