import {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";
import {
  ClientAssignmentError,
  ClientAssignmentRecord,
  ClientAssignmentRepository,
} from "./client_assignment_service";

export class FirestoreClientAssignmentRepository
implements ClientAssignmentRepository {
  constructor(private readonly firestore: Firestore) {}

  async assign(record: ClientAssignmentRecord): Promise<ClientAssignmentRecord> {
    const reference = this.firestore.collection("client_assignments")
      .doc(record.clientId);
    return this.firestore.runTransaction(async transaction => {
      const snapshot = await transaction.get(reference);
      const previousVersion = snapshot.exists
        ? positiveVersion(snapshot.get("version")) ?? 1
        : 0;
      const sameDietitian = snapshot.exists &&
        snapshot.get("active") === true &&
        snapshot.get("dietitian_id") === record.dietitianId;
      const version = sameDietitian
        ? Math.max(1, previousVersion)
        : previousVersion + 1;
      const assignedAt = sameDietitian &&
        typeof snapshot.get("assigned_at") === "string"
        ? snapshot.get("assigned_at") as string
        : record.assignedAt;
      const assignedById = sameDietitian &&
        typeof snapshot.get("assigned_by_id") === "string"
        ? snapshot.get("assigned_by_id") as string
        : record.assignedById;
      const assigned: ClientAssignmentRecord = {
        ...record,
        assignedAt,
        assignedById,
        version,
      };
      const history = this.firestore.collection("client_assignment_history");
      const currentHistory = history.doc(historyDocumentId(
        assigned.clientId,
        assigned.version,
      ));

      if (sameDietitian) {
        const historySnapshot = await transaction.get(currentHistory);
        ensureHistoryEntry(
          transaction,
          historySnapshot,
          currentHistory,
          historyValues(assigned),
        );
        transaction.set(reference, currentAssignmentValues(assigned));
        return assigned;
      }

      if (snapshot.exists) {
        const previousDietitianId = snapshot.get("dietitian_id");
        if (typeof previousDietitianId !== "string" ||
            !/^[A-Za-z0-9_-]{1,128}$/.test(previousDietitianId)) {
          throw new ClientAssignmentError(
            503,
            "An existing client assignment needs attention.",
          );
        }
        const previousHistory = history.doc(historyDocumentId(
          record.clientId,
          previousVersion,
        ));
        const [previousHistorySnapshot, currentHistorySnapshot] =
          await Promise.all([
            transaction.get(previousHistory),
            transaction.get(currentHistory),
          ]);
        ensureHistoryEntry(
          transaction,
          previousHistorySnapshot,
          previousHistory,
          {
            active: snapshot.get("active") === true,
            client_id: record.clientId,
            dietitian_id: previousDietitianId,
            assigned_at: stringOrNull(snapshot.get("assigned_at")),
            assigned_by_id: stringOrNull(snapshot.get("assigned_by_id")),
            version: previousVersion,
          },
        );
        ensureHistoryEntry(
          transaction,
          currentHistorySnapshot,
          currentHistory,
          historyValues(assigned),
        );
      } else {
        const currentHistorySnapshot = await transaction.get(currentHistory);
        ensureHistoryEntry(
          transaction,
          currentHistorySnapshot,
          currentHistory,
          historyValues(assigned),
        );
      }
      transaction.set(reference, currentAssignmentValues(assigned));
      return assigned;
    });
  }

  async currentClientCounts(): Promise<Record<string, number>> {
    const snapshot = await this.firestore.collection("client_assignments")
      .where("active", "==", true).get();
    const counts: Record<string, number> = {};
    for (const document of snapshot.docs) {
      const dietitianId = document.get("dietitian_id");
      if (typeof dietitianId !== "string" ||
          !/^[A-Za-z0-9_-]{1,128}$/.test(dietitianId)) {
        throw new ClientAssignmentError(
          503,
          "An existing client assignment needs attention.",
        );
      }
      counts[dietitianId] = (counts[dietitianId] ?? 0) + 1;
    }
    return counts;
  }

  async getCurrent(clientId: string): Promise<ClientAssignmentRecord | null> {
    const snapshot = await this.firestore.collection("client_assignments")
      .doc(clientId).get();
    if (!snapshot.exists || snapshot.get("active") !== true) return null;
    const dietitianId = snapshot.get("dietitian_id");
    const assignedAt = snapshot.get("assigned_at");
    const assignedById = snapshot.get("assigned_by_id");
    const version = snapshot.get("version");
    if (typeof dietitianId !== "string" ||
        typeof assignedAt !== "string" ||
        typeof assignedById !== "string" ||
        !Number.isSafeInteger(version) || version < 1) {
      throw new ClientAssignmentError(
        503,
        "An existing client assignment needs attention.",
      );
    }
    return {
      clientId,
      dietitianId,
      active: true,
      assignedAt,
      assignedById,
      version,
    };
  }
}

type AssignmentHistoryValues = {
  active: boolean;
  client_id: string;
  dietitian_id: string;
  assigned_at: string | null;
  assigned_by_id: string | null;
  version: number;
};

function historyValues(record: ClientAssignmentRecord): AssignmentHistoryValues {
  return {
    active: record.active,
    client_id: record.clientId,
    dietitian_id: record.dietitianId,
    assigned_at: record.assignedAt,
    assigned_by_id: record.assignedById,
    version: record.version,
  };
}

function currentAssignmentValues(record: ClientAssignmentRecord) {
  return {
    active: true,
    client_id: record.clientId,
    dietitian_id: record.dietitianId,
    assigned_at: record.assignedAt,
    assigned_by_id: record.assignedById,
    version: record.version,
  };
}

function ensureHistoryEntry(
  transaction: Transaction,
  snapshot: DocumentSnapshot,
  reference: DocumentReference,
  values: AssignmentHistoryValues,
): void {
  if (!snapshot.exists) {
    transaction.create(reference, values);
    return;
  }
  if (!sameHistoryValues(snapshot.data(), values)) {
    throw new ClientAssignmentError(
      503,
      "An existing client assignment history entry needs attention.",
    );
  }
}

function sameHistoryValues(
  stored: DocumentData | undefined,
  expected: AssignmentHistoryValues,
): boolean {
  return stored !== undefined &&
    stored.active === expected.active &&
    stored.client_id === expected.client_id &&
    stored.dietitian_id === expected.dietitian_id &&
    (stored.assigned_at ?? null) === expected.assigned_at &&
    (stored.assigned_by_id ?? null) === expected.assigned_by_id &&
    stored.version === expected.version;
}

function historyDocumentId(clientId: string, version: number): string {
  return `${clientId}_v${version}`;
}

function positiveVersion(value: unknown): number | null {
  return Number.isSafeInteger(value) && (value as number) > 0
    ? value as number
    : null;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}
