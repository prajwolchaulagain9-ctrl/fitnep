import { Firestore } from "firebase-admin/firestore";
import {
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
}
