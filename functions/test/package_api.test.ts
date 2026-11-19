import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  AuthenticatedUser,
  CreatePackageResult,
  NewPackage,
  PackageRecord,
} from "../src/domain";
import { createNotificationApp } from "../src/http_app";
import {
  PackageRepository,
  PackageRequestConflictError,
} from "../src/package_repository";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

const admin: AuthenticatedUser = { uid: "admin-1", role: "admin" };
const client: AuthenticatedUser = { uid: "client-1", role: "client" };

describe("package API", () => {
  let repository: InMemoryPackageRepository;
  let api: ReturnType<typeof createNotificationApp>;

  beforeEach(() => {
    repository = new InMemoryPackageRepository();
    api = createNotificationApp({
      authVerifier: new FakeAuthVerifier({ admin, client }),
      notificationRepository: new InMemoryNotificationRepository(),
      packageRepository: repository,
    });
  });

  it("allows an admin to create and list a complete package", async () => {
    const createResponse = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send(validPackage());
    const listResponse = await request(api)
      .get("/packages")
      .set(bearer("client"));

    assert.equal(createResponse.status, 201);
    assert.deepEqual(createResponse.body.data.package, {
      id: "package-request-1",
      name: "Premium Fitness",
      duration_months: 3,
      price: 2500,
      feature_description: "Personalized training and nutrition guidance.",
      created_at: "2026-11-19T12:00:00.000Z",
    });
    assert.equal(listResponse.status, 200);
    assert.equal(listResponse.body.data.packages.length, 1);
  });

  it("rejects invalid fields and non-admin creation", async () => {
    const invalidName = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send({ ...validPackage(), name: " " });
    const invalidDuration = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send({ ...validPackage(), duration_months: 0 });
    const invalidPrice = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send({ ...validPackage(), price: -1 });
    const invalidFeature = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send({ ...validPackage(), feature_description: "" });
    const clientCreate = await request(api)
      .post("/packages")
      .set(bearer("client"))
      .send(validPackage());

    assert.equal(invalidName.status, 400);
    assert.equal(invalidDuration.status, 400);
    assert.equal(invalidPrice.status, 400);
    assert.equal(invalidFeature.status, 400);
    assert.equal(clientCreate.status, 403);
    assert.equal(repository.records.length, 0);
  });

  it("makes repeated create requests idempotent", async () => {
    const first = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send(validPackage());
    const repeated = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send(validPackage());
    const conflict = await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send({ ...validPackage(), name: "Different package" });

    assert.equal(first.status, 201);
    assert.equal(repeated.status, 201);
    assert.equal(repeated.body.data.package.id, first.body.data.package.id);
    assert.equal(conflict.status, 409);
    assert.equal(repository.records.length, 1);
  });
});

class InMemoryPackageRepository implements PackageRepository {
  readonly records: PackageRecord[] = [];

  async list(): Promise<PackageRecord[]> {
    return [...this.records];
  }

  async createIfAbsent(input: NewPackage): Promise<CreatePackageResult> {
    const existing = this.records.find(
      (record) => record.requestId === input.requestId,
    );
    if (existing !== undefined) {
      if (
        existing.name !== input.name ||
        existing.durationMonths !== input.durationMonths ||
        existing.price !== input.price ||
        existing.featureDescription !== input.featureDescription ||
        existing.createdBy !== input.createdBy
      ) {
        throw new PackageRequestConflictError();
      }
      return { package: existing, created: false };
    }
    const record: PackageRecord = {
      id: input.requestId,
      ...input,
      createdAt: "2026-11-19T12:00:00.000Z",
    };
    this.records.push(record);
    return { package: record, created: true };
  }
}

class FakeAuthVerifier implements AuthVerifier {
  constructor(private readonly users: Record<string, AuthenticatedUser>) {}

  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    const user = this.users[token];
    if (user === undefined) throw new AuthenticationError("Invalid token.");
    return user;
  }
}

function validPackage() {
  return {
    request_id: "package-request-1",
    name: " Premium Fitness ",
    duration_months: 3,
    price: 2500,
    feature_description: " Personalized training and nutrition guidance. ",
  };
}

function bearer(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` };
}
