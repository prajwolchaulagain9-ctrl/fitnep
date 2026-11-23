import assert from "node:assert/strict";
import { describe, it } from "node:test";
import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  AssignmentPackageStatus,
  ClientAssignmentRecord,
  ClientAssignmentRepository,
  ClientAssignmentService,
  ClientPackageStatusReader,
  DietitianDirectory,
  inactivePackageAssignmentMessage,
} from "../src/client_assignment_service";
import { AuthenticatedUser } from "../src/domain";
import { createNotificationApp } from "../src/http_app";
import { InMemoryNotificationRepository } from "./in_memory_notification_repository";

const admin: AuthenticatedUser = { uid: "admin-1", role: "admin" };
const client: AuthenticatedUser = { uid: "client-1", role: "client" };

describe("client assignment package validation", () => {
  it("allows an active-package client to be assigned", async () => {
    const fixture = createFixture("active");

    const eligibility = await request(fixture.app)
      .get("/admin/client-assignments/client-1/eligibility")
      .set(bearer("admin"))
      .expect(200);
    assert.equal(eligibility.body.data.eligibility.can_assign, true);
    assert.equal(eligibility.body.data.eligibility.package_status, "active");

    const response = await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);

    assert.equal(response.body.data.assignment.client_id, "client-1");
    assert.equal(response.body.data.assignment.dietitian_id, "dietitian-1");
    assert.equal(fixture.assignments.records.length, 1);
  });

  for (const status of [
    "pending", "scheduled", "expired", "inactive", "none",
  ] as const) {
    it(`prevents assignment when the package is ${status}`, async () => {
      const fixture = createFixture(status);

      const eligibility = await request(fixture.app)
        .get("/admin/client-assignments/client-1/eligibility")
        .set(bearer("admin"))
        .expect(200);
      assert.equal(eligibility.body.data.eligibility.can_assign, false);
      assert.equal(
        eligibility.body.data.eligibility.message,
        inactivePackageAssignmentMessage,
      );

      const response = await request(fixture.app)
        .put("/admin/client-assignments/client-1")
        .set(bearer("admin"))
        .send({ dietitian_id: "dietitian-1" })
        .expect(409);
      assert.equal(response.body.error, inactivePackageAssignmentMessage);
      assert.equal(fixture.assignments.records.length, 0);
    });
  }

  it("re-checks package status when the assignment is submitted", async () => {
    const fixture = createFixture("active");
    await request(fixture.app)
      .get("/admin/client-assignments/client-1/eligibility")
      .set(bearer("admin"))
      .expect(200);

    fixture.packages.status = "expired";

    const response = await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(409);
    assert.equal(response.body.error, inactivePackageAssignmentMessage);
    assert.equal(fixture.assignments.records.length, 0);
  });

  it("returns current counts and updates them after reassignment", async () => {
    const fixture = createFixture("active");
    fixture.assignments.records.push(
      assignment("client-1", "dietitian-old"),
      assignment("client-2", "dietitian-1"),
      assignment("client-3", "dietitian-1"),
    );

    const before = await request(fixture.app)
      .get("/admin/client-assignments/dietitian-counts")
      .set(bearer("admin"))
      .expect(200);
    assert.deepEqual(before.body.data.counts, {
      "dietitian-old": 1,
      "dietitian-1": 2,
    });

    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);

    const after = await request(fixture.app)
      .get("/admin/client-assignments/dietitian-counts")
      .set(bearer("admin"))
      .expect(200);
    assert.deepEqual(after.body.data.counts, { "dietitian-1": 3 });
  });

  it("does not allow a client account to use the admin assignment API", async () => {
    const fixture = createFixture("active");
    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("client"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(403);
    assert.equal(fixture.assignments.records.length, 0);
  });
});

function createFixture(status: AssignmentPackageStatus) {
  const assignments = new InMemoryAssignmentRepository();
  const packages = new MutablePackageStatusReader(status);
  const service = new ClientAssignmentService(
    assignments,
    packages,
    new ActiveDietitianDirectory(),
    () => new Date("2026-11-23T12:00:00.000Z"),
  );
  return {
    assignments,
    packages,
    app: createNotificationApp({
      authVerifier: new FakeAuthVerifier({ admin, client }),
      notificationRepository: new InMemoryNotificationRepository(),
      clientAssignmentService: service,
    }),
  };
}

class InMemoryAssignmentRepository implements ClientAssignmentRepository {
  readonly records: ClientAssignmentRecord[] = [];

  async assign(record: ClientAssignmentRecord): Promise<ClientAssignmentRecord> {
    const index = this.records.findIndex(item => item.clientId === record.clientId);
    if (index === -1) this.records.push(record);
    else this.records[index] = record;
    return record;
  }

  async currentClientCounts(): Promise<Record<string, number>> {
    return this.records.reduce<Record<string, number>>((counts, record) => {
      counts[record.dietitianId] = (counts[record.dietitianId] ?? 0) + 1;
      return counts;
    }, {});
  }
}

class MutablePackageStatusReader implements ClientPackageStatusReader {
  constructor(public status: AssignmentPackageStatus) {}
  async getStatus(): Promise<AssignmentPackageStatus> { return this.status; }
}

class ActiveDietitianDirectory implements DietitianDirectory {
  async isActiveDietitian(uid: string): Promise<boolean> {
    return uid === "dietitian-1";
  }
}

class FakeAuthVerifier implements AuthVerifier {
  constructor(private readonly users: Record<string, AuthenticatedUser>) {}

  async verifyIdToken(token: string): Promise<AuthenticatedUser> {
    const user = this.users[token];
    if (!user) throw new AuthenticationError("Invalid token.");
    return user;
  }
}

function bearer(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` };
}

function assignment(clientId: string, dietitianId: string): ClientAssignmentRecord {
  return {
    clientId,
    dietitianId,
    active: true,
    assignedAt: "2026-11-23T12:00:00.000Z",
    assignedById: "admin-1",
  };
}
