import assert from "node:assert/strict";
import { describe, it } from "node:test";
import request from "supertest";

import { AuthVerifier, AuthenticationError } from "../src/auth";
import {
  AssignedClientDirectory,
  AssignedClientProfile,
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
import { NotificationWorkflowService } from "../src/notification_service";

const admin: AuthenticatedUser = { uid: "admin-1", role: "admin" };
const client: AuthenticatedUser = { uid: "client-1", role: "client" };
const dietitian: AuthenticatedUser = { uid: "dietitian-1", role: "dietitian" };
const otherDietitian: AuthenticatedUser = { uid: "dietitian-2", role: "dietitian" };

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

describe("dietitian client visibility and notification (acceptance criterion)", () => {
  it("preserves history and switches access when a client is reassigned", async () => {
    const fixture = createFixture("active");

    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);
    await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-1"))
      .expect(200);
    await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-2"))
      .expect(403);

    const reassigned = await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-2" })
      .expect(200);

    assert.equal(reassigned.body.data.assignment.dietitian_id, "dietitian-2");
    assert.equal(fixture.assignments.records[0]?.dietitianId, "dietitian-2");
    assert.deepEqual(
      fixture.assignments.history.map(item => [item.version, item.dietitianId]),
      [[1, "dietitian-1"], [2, "dietitian-2"]],
    );
    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-2" })
      .expect(200);
    assert.deepEqual(
      fixture.assignments.history.map(item => [item.version, item.dietitianId]),
      [[1, "dietitian-1"], [2, "dietitian-2"]],
    );
    await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-1"))
      .expect(403);
    await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-2"))
      .expect(200);
  });

  it("assigned dietitian receives a notification after assignment", async () => {
    const fixture = createFixture("active");

    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);

    const dietitianNotifications = await fixture.notifications.listForRecipient("dietitian-1");
    assert.equal(dietitianNotifications.length, 1);
    assert.equal(dietitianNotifications[0]?.type, "assignment");
    assert.equal(dietitianNotifications[0]?.referenceId, "client-1");
  });

  it("assigned dietitian can view the assigned client", async () => {
    const fixture = createFixture("active");

    // Assign the client
    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);

    // Assigned dietitian can view the client
    const response = await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-1"))
      .expect(200);

    assert.equal(response.body.data.client.id, "client-1");
    assert.equal(response.body.data.client.assignment_status, "active");
  });

  it("unassigned dietitian cannot view the client", async () => {
    const fixture = createFixture("active");

    // Assign to dietitian-1
    await request(fixture.app)
      .put("/admin/client-assignments/client-1")
      .set(bearer("admin"))
      .send({ dietitian_id: "dietitian-1" })
      .expect(200);

    // dietitian-2 (not assigned) cannot see the client
    const response = await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-2"))
      .expect(403);

    assert.ok(response.body.error.includes("not currently assigned"));
  });

  it("admin cannot use the dietitian client view endpoint", async () => {
    const fixture = createFixture("active");
    fixture.assignments.records.push(assignment("client-1", "dietitian-1"));

    await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("admin"))
      .expect(403);
  });

  it("unassigned client returns 403 before any assignment is made", async () => {
    const fixture = createFixture("active");

    await request(fixture.app)
      .get("/dietitian/assigned-clients/client-1")
      .set(bearer("dietitian-1"))
      .expect(403);
  });
});

function createFixture(status: AssignmentPackageStatus) {
  const assignments = new InMemoryAssignmentRepository();
  const packages = new MutablePackageStatusReader(status);
  const notifications = new InMemoryNotificationRepository();
  const service = new ClientAssignmentService(
    assignments,
    packages,
    new ActiveDietitianDirectory(),
    new NotificationWorkflowService(notifications, {
      now: () => new Date("2026-11-23T12:00:00.000Z"),
      idFactory: (() => { let n = 0; return () => `notification-${++n}`; })(),
    }),
    new FakeClientDirectory(),
    () => new Date("2026-11-23T12:00:00.000Z"),
  );
  return {
    assignments,
    packages,
    notifications,
    app: createNotificationApp({
      authVerifier: new FakeAuthVerifier({
        admin,
        client,
        "dietitian-1": dietitian,
        "dietitian-2": otherDietitian,
      }),
      notificationRepository: notifications,
      clientAssignmentService: service,
    }),
  };
}

class InMemoryAssignmentRepository implements ClientAssignmentRepository {
  readonly records: ClientAssignmentRecord[] = [];
  readonly history: ClientAssignmentRecord[] = [];

  async assign(record: ClientAssignmentRecord): Promise<ClientAssignmentRecord> {
    const index = this.records.findIndex(item => item.clientId === record.clientId);
    const previous = index === -1 ? null : this.records[index] ?? null;
    const sameDietitian = previous?.dietitianId === record.dietitianId;
    const version = previous === null
      ? (record.version > 0 ? record.version : 1)
      : sameDietitian
        ? previous.version
        : Math.max(1, previous.version + 1);
    const stored = sameDietitian && previous !== null
      ? previous
      : { ...record, version };
    if (index === -1) this.records.push(stored);
    else this.records[index] = stored;
    if (!this.history.some(item =>
      item.clientId === stored.clientId && item.version === stored.version
    )) {
      this.history.push(stored);
    }
    return stored;
  }

  async currentClientCounts(): Promise<Record<string, number>> {
    return this.records.reduce<Record<string, number>>((counts, record) => {
      counts[record.dietitianId] = (counts[record.dietitianId] ?? 0) + 1;
      return counts;
    }, {});
  }

  async getCurrent(clientId: string): Promise<ClientAssignmentRecord | null> {
    return this.records.find(r => r.clientId === clientId && r.active) ?? null;
  }
}

class FakeClientDirectory implements AssignedClientDirectory {
  async getClient(clientId: string): Promise<AssignedClientProfile> {
    return { id: clientId, name: `Client ${clientId}`, email: `${clientId}@example.com` };
  }
}

class MutablePackageStatusReader implements ClientPackageStatusReader {
  constructor(public status: AssignmentPackageStatus) {}
  async getStatus(): Promise<AssignmentPackageStatus> { return this.status; }
}

class ActiveDietitianDirectory implements DietitianDirectory {
  async isActiveDietitian(uid: string): Promise<boolean> {
    return uid === "dietitian-1" || uid === "dietitian-2";
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
    version: 1,
  };
}
