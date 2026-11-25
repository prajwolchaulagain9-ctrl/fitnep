import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { Firestore, Transaction } from "firebase-admin/firestore";

import { AuditEventInput } from "../src/audit";
import { FirestoreClientIntakeRepository } from "../src/firestore_client_intake_repository";

describe("Firestore client intake review persistence", () => {
  it("persists reviewed as the status and selected action", async () => {
    const fixture = createFixture();

    const intake = await fixture.repository.updateReviewForAssignedDietitian(
      "client-1",
      "dietitian-1",
      { action: "reviewed", note: null, status: "reviewed" },
      {
        actor: { uid: "dietitian-1", role: "dietitian" },
        correlationId: "request-reviewed",
      },
    );

    assert.equal(fixture.firestore.savedUpdate?.status, "reviewed");
    assert.equal(fixture.firestore.savedUpdate?.review_action, "reviewed");
    assert.equal(fixture.firestore.savedUpdate?.reviewed_by_id, "dietitian-1");
    assert.equal(fixture.auditInput?.action, "intake.reviewed");
    assert.equal(intake.status, "reviewed");
  });

  it("persists a missing-information request and its note", async () => {
    const fixture = createFixture();

    const intake = await fixture.repository.updateReviewForAssignedDietitian(
      "client-1",
      "dietitian-1",
      {
        action: "missing_information",
        note: "Please provide the current medication dosage.",
        status: "information_requested",
      },
      {
        actor: { uid: "dietitian-1", role: "dietitian" },
        correlationId: "request-missing",
      },
    );

    assert.equal(
      fixture.firestore.savedUpdate?.status,
      "information_requested",
    );
    assert.equal(
      fixture.firestore.savedUpdate?.review_action,
      "missing_information",
    );
    assert.equal(
      fixture.firestore.savedUpdate?.review_note,
      "Please provide the current medication dosage.",
    );
    assert.equal(fixture.auditInput?.action, "intake.information_requested");
    assert.equal(intake.review.action, "missing_information");
  });
});

function createFixture() {
  const firestore = new FakeFirestore();
  let auditInput: AuditEventInput | null = null;
  const repository = new FirestoreClientIntakeRepository(
    firestore as unknown as Firestore,
    {
      appendWithEvent: (_transaction, input) => { auditInput = input; return "audit-1"; },
      appendInTransaction: (
        _transaction: Transaction,
        input: AuditEventInput,
      ) => {
        auditInput = input;
        return "audit-1";
      },
    },
    { readResource: (_actor, _target, load) => firestore.runTransaction(async transaction =>
      (await load(transaction as unknown as Transaction)).data) },
  );
  return {
    firestore,
    repository,
    get auditInput(): AuditEventInput | null {
      return auditInput;
    },
  };
}

class FakeFirestore {
  savedUpdate: Record<string, unknown> | null = null;

  collection(name: string) {
    return {
      doc: (id: string) => ({ path: `${name}/${id}` }),
    };
  }

  async runTransaction<T>(
    operation: (transaction: FakeTransaction) => Promise<T>,
  ): Promise<T> {
    return operation(new FakeTransaction(this));
  }
}

class FakeTransaction {
  constructor(private readonly firestore: FakeFirestore) {}

  async get(reference: { path: string }) {
    if (reference.path === "client_assignments/client-1") {
      return new FakeSnapshot({
        active: true,
        dietitian_id: "dietitian-1",
      });
    }
    return new FakeSnapshot({
      client_id: "client-1",
      allergies: [],
      medical_conditions: [],
      health_information: {},
      goals: {},
      restrictions: {},
      responses: {},
      submitted_at: "2026-11-20T08:00:00.000Z",
      status: "submitted",
    });
  }

  update(_reference: { path: string }, data: Record<string, unknown>): void {
    this.firestore.savedUpdate = data;
  }
  create(_reference: unknown, _data: unknown): void {}
}

class FakeSnapshot {
  constructor(private readonly value: Record<string, unknown>) {}

  get exists(): boolean {
    return true;
  }

  get(field: string): unknown {
    return this.value[field];
  }

  data(): Record<string, unknown> {
    return this.value;
  }
}
