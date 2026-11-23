import { Firestore } from "firebase-admin/firestore";
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
      const previousVersion = snapshot.exists &&
        Number.isSafeInteger(snapshot.get("version")) &&
        snapshot.get("version") > 0
        ? snapshot.get("version") as number
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
      transaction.set(reference, {
        active: true,
        client_id: assigned.clientId,
        dietitian_id: assigned.dietitianId,
        assigned_at: assigned.assignedAt,
        assigned_by_id: assigned.assignedById,
        version: assigned.version,
      });
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
