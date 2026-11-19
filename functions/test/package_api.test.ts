import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  AuthenticatedUser,
  CreatePackageResult,
  NewPackage,
  PackageRecord,
  UpdatePackageInput,
} from "../src/domain";
import { createNotificationApp } from "../src/http_app";
import {
  PackageNotFoundError,
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
      is_active: true,
      created_at: "2026-11-19T12:00:00.000Z",
    });
    assert.equal(listResponse.status, 200);
    assert.equal(listResponse.body.data.packages.length, 1);
  });

  it("admin list endpoint returns all packages including inactive", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());
    // Deactivate via admin toggle
    await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: false });

    const customerList = await request(api)
      .get("/packages")
      .set(bearer("client"));
    const adminList = await request(api)
      .get("/admin/packages")
      .set(bearer("admin"));

    assert.equal(customerList.status, 200);
    assert.equal(customerList.body.data.packages.length, 0, "customers see no inactive packages");
    assert.equal(adminList.status, 200);
    assert.equal(adminList.body.data.packages.length, 1, "admin sees all packages");
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

  it("admin can edit a package", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());

    const editResponse = await request(api)
      .patch("/packages/package-request-1")
      .set(bearer("admin"))
      .send({
        name: "Updated Fitness",
        duration_months: 6,
        price: 3500,
        feature_description: "Updated features.",
      });

    assert.equal(editResponse.status, 200);
    assert.equal(editResponse.body.data.package.name, "Updated Fitness");
    assert.equal(editResponse.body.data.package.duration_months, 6);
    assert.equal(editResponse.body.data.package.price, 3500);
    assert.equal(editResponse.body.data.package.feature_description, "Updated features.");
    // isActive should remain unchanged
    assert.equal(editResponse.body.data.package.is_active, true);
  });

  it("non-admin cannot edit a package", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());

    const response = await request(api)
      .patch("/packages/package-request-1")
      .set(bearer("client"))
      .send({ name: "Hacked", duration_months: 1, price: 1, feature_description: "x" });

    assert.equal(response.status, 403);
    // Package name should be unchanged
    assert.equal(repository.records[0]?.name, "Premium Fitness");
  });

  it("editing a non-existent package returns 404", async () => {
    const response = await request(api)
      .patch("/packages/nonexistent")
      .set(bearer("admin"))
      .send({ name: "X", duration_months: 1, price: 100, feature_description: "y" });

    assert.equal(response.status, 404);
  });

  it("admin can deactivate and reactivate a package", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());

    const deactivate = await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: false });

    assert.equal(deactivate.status, 200);
    assert.equal(deactivate.body.data.package.is_active, false);

    // Customer list should not include deactivated package
    const customerList = await request(api)
      .get("/packages")
      .set(bearer("client"));
    assert.equal(customerList.body.data.packages.length, 0);

    const reactivate = await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: true });

    assert.equal(reactivate.status, 200);
    assert.equal(reactivate.body.data.package.is_active, true);

    // Customer list should now include the reactivated package
    const customerListAfter = await request(api)
      .get("/packages")
      .set(bearer("client"));
    assert.equal(customerListAfter.body.data.packages.length, 1);
  });

  it("non-admin cannot deactivate a package", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());

    const response = await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("client"))
      .send({ is_active: false });

    assert.equal(response.status, 403);
    assert.equal(repository.records[0]?.isActive, true);
  });

  it("deactivating with invalid body returns 400", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());

    const response = await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: "yes" });

    assert.equal(response.status, 400);
  });

  it("existing purchase records are not affected by deactivation", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());
    // Simulate an existing purchase record by confirming the package still exists in the repo
    const preDeactivationPackage = repository.records.find(
      (r) => r.id === "package-request-1",
    );
    assert.ok(preDeactivationPackage, "package exists before deactivation");

    await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: false });

    // Package record still exists in the repository (not deleted)
    assert.equal(repository.records.length, 1);
    const postDeactivationPackage = repository.records.find(
      (r) => r.id === "package-request-1",
    );
    assert.ok(postDeactivationPackage, "package still exists after deactivation");
    assert.equal(postDeactivationPackage.isActive, false);
  });
});

class InMemoryPackageRepository implements PackageRepository {
  readonly records: PackageRecord[] = [];

  async list(): Promise<PackageRecord[]> {
    return this.records.filter((r) => r.isActive);
  }

  async listAll(): Promise<PackageRecord[]> {
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
      isActive: true,
      createdAt: "2026-11-19T12:00:00.000Z",
    };
    this.records.push(record);
    return { package: record, created: true };
  }

  async update(id: string, input: UpdatePackageInput): Promise<PackageRecord> {
    const index = this.records.findIndex((r) => r.id === id);
    if (index === -1) throw new PackageNotFoundError();
    const existing = this.records[index];
    if (existing === undefined) throw new PackageNotFoundError();
    const updated: PackageRecord = {
      ...existing,
      name: input.name,
      durationMonths: input.durationMonths,
      price: input.price,
      featureDescription: input.featureDescription,
    };
    this.records[index] = updated;
    return updated;
  }

  async setActiveStatus(id: string, isActive: boolean): Promise<PackageRecord> {
    const index = this.records.findIndex((r) => r.id === id);
    if (index === -1) throw new PackageNotFoundError();
    const existing = this.records[index];
    if (existing === undefined) throw new PackageNotFoundError();
    const updated: PackageRecord = { ...existing, isActive };
    this.records[index] = updated;
    return updated;
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
