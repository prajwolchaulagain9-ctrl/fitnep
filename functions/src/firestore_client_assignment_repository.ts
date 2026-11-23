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
    await this.firestore.collection("client_assignments").doc(record.clientId).set({
      active: true,
      client_id: record.clientId,
      dietitian_id: record.dietitianId,
      assigned_at: record.assignedAt,
      assigned_by_id: record.assignedById,
    });
    return record;
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
}
