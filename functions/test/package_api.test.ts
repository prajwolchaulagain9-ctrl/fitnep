import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  AuthenticatedUser,
  CreatePackageResult,
  NewPackage,
  PackageChangeHistoryRecord,
  PackageHistoryValues,
  PackageRecord,
  PurchaseRecord,
  SetPackageActiveStatusInput,
  UpdatePackageInput,
} from "../src/domain";
import { createNotificationApp } from "../src/http_app";
import { addCalendarMonths } from "../src/firestore_purchase_repository";
import {
  PackageNotFoundError,
  PackageRepository,
  PackageRequestConflictError,
} from "../src/package_repository";
import {
  PurchasablePackageNotFoundError,
  PurchaseRepository,
  PurchaseRequestConflictError,
} from "../src/purchase_repository";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

const admin: AuthenticatedUser = {
  uid: "admin-1",
  role: "admin",
  displayName: "FitNep CEO",
};
const client: AuthenticatedUser = { uid: "client-1", role: "client" };
const clientB: AuthenticatedUser = { uid: "client-2", role: "client" };

describe("package API", () => {
  let repository: InMemoryPackageRepository;
  let purchaseRepository: InMemoryPurchaseRepository;
  let api: ReturnType<typeof createNotificationApp>;

  beforeEach(() => {
    repository = new InMemoryPackageRepository();
    purchaseRepository = new InMemoryPurchaseRepository(repository);
    api = createNotificationApp({
      authVerifier: new FakeAuthVerifier({ admin, client, clientB }),
      notificationRepository: new InMemoryNotificationRepository(),
      packageRepository: repository,
      purchaseRepository,
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

  it("rejects frontend purchase identity, price and activation overrides", async () => {
    for (const extra of [{ customer_id: "client-2" }, { price_paid: 1 }, { status: "active" }]) {
      const response = await request(api).post("/purchases").set(bearer("client"))
        .send({ package_id: "premium", request_id: "purchase-security-01", ...extra });
      assert.equal(response.status, 400);
    }
    assert.equal(purchaseRepository.records.length, 0);
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
    assert.equal(repository.history.length, 1);
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

  it("records admin identity, time, actions, and changed values", async () => {
    await request(api)
      .post("/packages")
      .set(bearer("admin"))
      .send({
        ...validPackage(),
        admin_id: "forged-admin",
        admin_name: "Forged Name",
        changed_at: "2000-01-01T00:00:00.000Z",
      })
      .expect(201);
    await request(api)
      .patch("/packages/package-request-1")
      .set(bearer("admin"))
      .send({
        name: "Premium Plus",
        duration_months: 6,
        price: 6500,
        feature_description:
          "Diet Plan, Workout Plan, Personal Coaching",
      })
      .expect(200);
    await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: false })
      .expect(200);
    await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: true })
      .expect(200);

    const response = await request(api)
      .get("/admin/package-history")
      .set(bearer("admin"));

    assert.equal(response.status, 200);
    assert.equal(response.body.data.history.length, 4);
    const [activated, deactivated, updated, created] =
      response.body.data.history;
    assert.equal(created.action, "created");
    assert.equal(created.admin_id, "admin-1");
    assert.equal(created.admin_name, "FitNep CEO");
    assert.notEqual(created.changed_at, "2000-01-01T00:00:00.000Z");
    assert.deepEqual(updated.previous_values, {
      name: "Premium Fitness",
      duration_months: 3,
      price: 2500,
      feature_description:
        "Personalized training and nutrition guidance.",
    });
    assert.deepEqual(updated.new_values, {
      name: "Premium Plus",
      duration_months: 6,
      price: 6500,
      feature_description: "Diet Plan, Workout Plan, Personal Coaching",
    });
    assert.equal(deactivated.action, "deactivated");
    assert.deepEqual(deactivated.previous_values, { is_active: true });
    assert.deepEqual(deactivated.new_values, { is_active: false });
    assert.equal(activated.action, "activated");
    assert.deepEqual(activated.previous_values, { is_active: false });
    assert.deepEqual(activated.new_values, { is_active: true });

    const restartedApi = createNotificationApp({
      authVerifier: new FakeAuthVerifier({ admin, client, clientB }),
      notificationRepository: new InMemoryNotificationRepository(),
      packageRepository: repository,
      purchaseRepository,
    });
    const afterRestart = await request(restartedApi)
      .get("/admin/package-history")
      .set(bearer("admin"));
    assert.equal(afterRestart.body.data.history.length, 4);
  });

  it("rejects non-admin history access and skips no-op duplicates", async () => {
    await request(api).post("/packages").set(bearer("admin")).send(validPackage());
    await request(api)
      .patch("/packages/package-request-1")
      .set(bearer("admin"))
      .send({
        name: "Premium Fitness",
        duration_months: 3,
        price: 2500,
        feature_description:
          "Personalized training and nutrition guidance.",
      })
      .expect(200);
    await request(api)
      .patch("/packages/package-request-1/active")
      .set(bearer("admin"))
      .send({ is_active: true })
      .expect(200);

    assert.equal(repository.history.length, 1);
    const forbidden = await request(api)
      .get("/admin/package-history")
      .set(bearer("client"));
    assert.equal(forbidden.status, 403);
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

  it("snapshots purchased terms while future purchases receive package edits", async () => {
    await request(api).post("/packages").set(bearer("admin")).send({
      request_id: "premium-package-request",
      name: "Premium",
      duration_months: 3,
      price: 5000,
      feature_description: "Diet Plan, Workout Plan, Weekly Consultation",
    });

    const customerAPurchase = await request(api)
      .post("/purchases")
      .set(bearer("client"))
      .send({
        package_id: "premium-package-request",
        request_id: "customer-a-purchase-1",
      });
    assert.equal(customerAPurchase.status, 201);

    await request(api)
      .patch("/packages/premium-package-request")
      .set(bearer("admin"))
      .send({
        name: "Premium Plus",
        duration_months: 6,
        price: 6500,
        feature_description:
          "Diet Plan, Workout Plan, Personal Coaching, Priority Consultation",
      });

    const customerAAfterEdit = await request(api)
      .get("/purchases/current")
      .set(bearer("client"));
    assert.deepEqual(customerAAfterEdit.body.data.purchase, {
      id: "customer-a-purchase-1",
      package_id: "premium-package-request",
      package_name: "Premium",
      price_paid: 5000,
      duration_months: 3,
      feature_description: "Diet Plan, Workout Plan, Weekly Consultation",
      purchased_at: "2026-01-31T12:00:00.000Z",
      expires_at: "2026-04-30T12:00:00.000Z",
    });

    const customerBPurchase = await request(api)
      .post("/purchases")
      .set(bearer("clientB"))
      .send({
        package_id: "premium-package-request",
        request_id: "customer-b-purchase-1",
      });
    assert.equal(customerBPurchase.status, 201);
    assert.equal(customerBPurchase.body.data.purchase.package_name, "Premium Plus");
    assert.equal(customerBPurchase.body.data.purchase.price_paid, 6500);
    assert.equal(customerBPurchase.body.data.purchase.duration_months, 6);
    assert.equal(
      customerBPurchase.body.data.purchase.feature_description,
      "Diet Plan, Workout Plan, Personal Coaching, Priority Consultation",
    );

    const restartedApi = createNotificationApp({
      authVerifier: new FakeAuthVerifier({ admin, client, clientB }),
      notificationRepository: new InMemoryNotificationRepository(),
      packageRepository: repository,
      purchaseRepository,
    });
    const afterRestart = await request(restartedApi)
      .get("/purchases/current")
      .set(bearer("client"));
    assert.equal(afterRestart.body.data.purchase.price_paid, 5000);
    assert.equal(
      afterRestart.body.data.purchase.expires_at,
      "2026-04-30T12:00:00.000Z",
    );
  });
});

class InMemoryPackageRepository implements PackageRepository {
  readonly records: PackageRecord[] = [];
  readonly history: PackageChangeHistoryRecord[] = [];

  async list(): Promise<PackageRecord[]> {
    return this.records.filter((r) => r.isActive);
  }

  async listAll(): Promise<PackageRecord[]> {
    return [...this.records];
  }

  async listHistory(): Promise<PackageChangeHistoryRecord[]> {
    return [...this.history].reverse();
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
    this.addHistory({
      packageId: record.id,
      packageName: record.name,
      adminId: input.createdBy,
      adminName: input.createdByName,
      action: "created",
      previousValues: null,
      newValues: packageValues(record),
    });
    return { package: record, created: true };
  }

  async update(id: string, input: UpdatePackageInput): Promise<PackageRecord> {
    const index = this.records.findIndex((r) => r.id === id);
    if (index === -1) throw new PackageNotFoundError();
    const existing = this.records[index];
    if (existing === undefined) throw new PackageNotFoundError();
    const previousValues: PackageHistoryValues = {};
    const newValues: PackageHistoryValues = {};
    captureChange(previousValues, newValues, "name", existing.name, input.name);
    captureChange(
      previousValues,
      newValues,
      "durationMonths",
      existing.durationMonths,
      input.durationMonths,
    );
    captureChange(previousValues, newValues, "price", existing.price, input.price);
    captureChange(
      previousValues,
      newValues,
      "featureDescription",
      existing.featureDescription,
      input.featureDescription,
    );
    if (Object.keys(newValues).length === 0) return existing;
    const updated: PackageRecord = {
      ...existing,
      name: input.name,
      durationMonths: input.durationMonths,
      price: input.price,
      featureDescription: input.featureDescription,
    };
    this.records[index] = updated;
    this.addHistory({
      packageId: updated.id,
      packageName: updated.name,
      adminId: input.updatedBy,
      adminName: input.updatedByName,
      action: "updated",
      previousValues,
      newValues,
    });
    return updated;
  }

  async setActiveStatus(
    id: string,
    input: SetPackageActiveStatusInput,
  ): Promise<PackageRecord> {
    const index = this.records.findIndex((r) => r.id === id);
    if (index === -1) throw new PackageNotFoundError();
    const existing = this.records[index];
    if (existing === undefined) throw new PackageNotFoundError();
    if (existing.isActive === input.isActive) return existing;
    const updated: PackageRecord = { ...existing, isActive: input.isActive };
    this.records[index] = updated;
    this.addHistory({
      packageId: updated.id,
      packageName: updated.name,
      adminId: input.updatedBy,
      adminName: input.updatedByName,
      action: input.isActive ? "activated" : "deactivated",
      previousValues: { isActive: existing.isActive },
      newValues: { isActive: input.isActive },
    });
    return updated;
  }

  private addHistory(
    input: Omit<PackageChangeHistoryRecord, "id" | "changedAt">,
  ): void {
    const sequence = this.history.length + 1;
    this.history.push({
      id: `history-${sequence}`,
      ...input,
      changedAt: new Date(
        Date.UTC(2026, 10, 19, 12, sequence),
      ).toISOString(),
    });
  }
}

function packageValues(record: PackageRecord): PackageHistoryValues {
  return {
    name: record.name,
    durationMonths: record.durationMonths,
    price: record.price,
    featureDescription: record.featureDescription,
    isActive: record.isActive,
  };
}

function captureChange<K extends keyof PackageHistoryValues>(
  previousValues: PackageHistoryValues,
  newValues: PackageHistoryValues,
  key: K,
  previous: PackageHistoryValues[K],
  next: PackageHistoryValues[K],
): void {
  if (previous !== next) {
    previousValues[key] = previous;
    newValues[key] = next;
  }
}

class InMemoryPurchaseRepository implements PurchaseRepository {
  readonly records: PurchaseRecord[] = [];

  constructor(private readonly packages: InMemoryPackageRepository) {}

  async getLatestForCustomer(
    customerId: string,
  ): Promise<PurchaseRecord | null> {
    return [...this.records]
      .filter((record) => record.customerId === customerId)
      .sort((left, right) =>
        (right.purchasedAt ?? "").localeCompare(left.purchasedAt ?? "")
      )[0] ?? null;
  }

  async purchasePackage(
    customerId: string,
    packageId: string,
    requestId: string,
  ): Promise<{ purchase: PurchaseRecord; created: boolean }> {
    const existing = this.records.find(
      (record) =>
        record.customerId === customerId && record.requestId === requestId,
    );
    if (existing !== undefined) {
      if (existing.packageId !== packageId) {
        throw new PurchaseRequestConflictError();
      }
      return { purchase: existing, created: false };
    }

    const source = this.packages.records.find(
      (record) => record.id === packageId && record.isActive,
    );
    if (source === undefined) throw new PurchasablePackageNotFoundError();

    const purchasedAt = new Date("2026-01-31T12:00:00.000Z");
    const purchase: PurchaseRecord = {
      id: requestId,
      customerId,
      packageId: source.id,
      packageName: source.name,
      pricePaid: source.price,
      durationMonths: source.durationMonths,
      featureDescription: source.featureDescription,
      purchasedAt: purchasedAt.toISOString(),
      expiresAt: addCalendarMonths(
        purchasedAt,
        source.durationMonths,
      ).toISOString(),
      requestId,
    };
    this.records.push(purchase);
    return { purchase, created: true };
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
