import { Transaction } from "firebase-admin/firestore";

import { AuditEventInput, AuditWriter } from "./audit";
import { AuthenticatedUser } from "./domain";
import { PrivateRecordAccessService } from "./nutrition_record_access_service";
import { recordSharingChoices } from "./private_records";

/** Later producers use the same policy without exposing unfinished workflows. */
export const healthSharingChoices = {
  ...recordSharingChoices,
  "diet-plans": "shareNutritionRecords",
  "weight-history": "shareNutritionRecords",
  messages: "shareNutritionRecords",
  intakes: "shareNutritionRecords",
} as const;

export interface HealthReadTarget {
  clientId: string;
  category: keyof typeof healthSharingChoices;
  recordId?: string;
  ownerOnly?: boolean;
  version?: number;
}

export function healthAuditTarget(target: HealthReadTarget): Pick<AuditEventInput, "targetType" | "targetId" | "clientId" | "version"> {
  return {
    targetType: target.recordId === undefined ? "record_collection" : "health_record",
    targetId: [target.clientId, target.category, target.recordId].filter(value => value !== undefined).join("/"),
    clientId: target.clientId,
    ...(target.version === undefined ? {} : { version: target.version }),
  };
}

/** Assignment, consent, data and audit commit together before any response. */
export class AuditedHealthReadService {
  constructor(
    private readonly access: PrivateRecordAccessService,
    private readonly audit: Pick<AuditWriter, "appendInTransaction">,
  ) {}

  async read<T>(
    transaction: Transaction,
    actor: AuthenticatedUser,
    target: HealthReadTarget,
    correlationId: string,
    load: () => Promise<{ data: T; recordIds?: readonly string[] }>,
  ): Promise<T> {
    const team = await this.access.assertCanRead(actor, target.clientId,
      healthSharingChoices[target.category], target.ownerOnly);
    const { data, recordIds } = await load();
    this.audit.appendInTransaction(transaction, {
      actor, action: "health.read", outcome: "succeeded", correlationId,
      ...healthAuditTarget(target),
      ...(team ? { dietitianId: team.dietitianId } : {}),
      ...(recordIds === undefined ? {} : { recordIds }),
    });
    return data;
  }
}
