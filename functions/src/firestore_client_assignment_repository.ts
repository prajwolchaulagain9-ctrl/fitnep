import { Firestore } from "firebase-admin/firestore";
import { accountFrom, accountMatchesActor, getCurrentAssignment } from "./account_service";
import { AuthenticatedUser } from "./domain";
import { FirestorePackageService, inactivePackageAssignmentMessage } from "./package_membership_service";
import {
  ClientAssignmentError,
  ClientAssignmentRecord,
  ClientAssignmentRepository,
} from "./client_assignment_service";

export class FirestoreClientAssignmentRepository
implements ClientAssignmentRepository {
  constructor(private readonly firestore: Firestore) {}

  async assign(record: ClientAssignmentRecord, expectedActor?: AuthenticatedUser): Promise<ClientAssignmentRecord> {
    const reference = this.firestore.collection("client_assignments")
      .doc(record.clientId);
    return this.firestore.runTransaction(async transaction => {
      const readAccount = async (uid: string) => accountFrom(uid,
        (await transaction.get(this.firestore.collection("users").doc(uid))).data());
      const [actor, client, dietitian] = await Promise.all([
        readAccount(record.assignedById), readAccount(record.clientId), readAccount(record.dietitianId),
      ]);
      if (actor.role !== "admin" || actor.account_status !== "active" ||
        (expectedActor !== undefined && !accountMatchesActor(actor, expectedActor)) ||
        client.role !== "client" || client.account_status !== "active" ||
        dietitian.role !== "dietitian" || dietitian.account_status !== "active") {
        throw new ClientAssignmentError(403, "Assignments require current active accounts with the matching roles.");
      }
      const snapshot = await transaction.get(reference);
      if (await new FirestorePackageService(this.firestore).assignmentStatus(record.clientId, transaction) !== "active") {
        throw new ClientAssignmentError(409, inactivePackageAssignmentMessage);
      }
      const previousVersion = snapshot.exists &&
        Number.isSafeInteger(snapshot.get("version")) &&
        snapshot.get("version") > 0
        ? snapshot.get("version") as number
        : 0;
      const sameDietitian = snapshot.exists &&
        snapshot.get("active") === true &&
        snapshot.get("dietitian_id") === record.dietitianId &&
        (snapshot.get("client_role_revision") ?? 0) === client.role_revision &&
        (snapshot.get("dietitian_role_revision") ?? 0) === dietitian.role_revision;
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
        client_role_revision: client.role_revision,
        dietitian_role_revision: dietitian.role_revision,
        team_member_ids: sameDietitian ? (snapshot.get("team_member_ids") ?? snapshot.get("staff_ids") ?? []) : [],
        staff_ids: sameDietitian ? (snapshot.get("team_member_ids") ?? snapshot.get("staff_ids") ?? []) : [],
        team_member_role_revisions: sameDietitian ? (snapshot.get("team_member_role_revisions") ?? snapshot.get("staff_role_revisions") ?? {}) : {},
        staff_role_revisions: sameDietitian ? (snapshot.get("team_member_role_revisions") ?? snapshot.get("staff_role_revisions") ?? {}) : {},
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
      const assignment = await getCurrentAssignment(this.firestore, document.id);
      if (!assignment) continue;
      const dietitianId = assignment.team.dietitianId;
      counts[dietitianId] = (counts[dietitianId] ?? 0) + 1;
    }
    return counts;
  }

  async getCurrent(clientId: string, actor?: AuthenticatedUser): Promise<ClientAssignmentRecord | null> {
    return this.firestore.runTransaction(async transaction => {
      const current = await getCurrentAssignment(this.firestore, clientId, transaction);
      if (!current) return null;
      if (actor !== undefined) {
        const account = accountFrom(actor.uid,
          (await transaction.get(this.firestore.collection("users").doc(actor.uid))).data());
        if (!accountMatchesActor(account, actor) || current.team.dietitianId !== actor.uid) return null;
      }
      const { dietitian_id: dietitianId, assigned_at: assignedAt, assigned_by_id: assignedById, version } = current.data;
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
    });
  }
}
