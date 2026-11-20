import {
  DocumentData,
  DocumentSnapshot,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import { CreatePurchaseResult, PurchaseRecord } from "./domain";
import { createHash } from "node:crypto";
import { FirestorePackageService } from "./package_membership_service";
export { addCalendarMonths } from "./package_membership_service";
import {
  PurchaseRepository,
  PurchaseRequestConflictError,
} from "./purchase_repository";

const customerPurchasesCollection = "customer_purchases";
const purchasesSubcollection = "purchases";

const fields = {
  customerId: "customer_id",
  packageId: "package_id",
  packageName: "package_name",
  pricePaid: "price_paid",
  durationMonths: "duration_months",
  featureDescription: "feature_description",
  purchasedAt: "purchased_at",
  expiresAt: "expires_at",
  requestId: "request_id",
  isActive: "is_active",
} as const;

export class FirestorePurchaseRepository implements PurchaseRepository {
  private readonly memberships: FirestorePackageService;
  constructor(private readonly firestore: Firestore) {
    this.memberships = new FirestorePackageService(firestore);
  }

  async getLatestForCustomer(
    customerId: string,
  ): Promise<PurchaseRecord | null> {
    const memberships = await this.memberships.memberships(customerId);
    if (memberships[0] !== undefined) return fromMembership(memberships[0]);
    const snapshot = await this.purchases(customerId)
      .orderBy(fields.purchasedAt, "desc")
      .limit(1)
      .get();
    const document = snapshot.docs[0];
    return document === undefined ? null : fromSnapshot(document);
  }

  async purchasePackage(
    customerId: string,
    packageId: string,
    requestId: string,
  ): Promise<CreatePurchaseResult> {
    // Existing purchases keep their immutable historical terms on retry.
    const archived = await this.purchases(customerId).doc(requestId).get();
    if (archived.exists) {
      const existing = fromSnapshot(archived);
      if (existing.packageId !== packageId) throw new PurchaseRequestConflictError();
      return { purchase: existing, created: false };
    }
    // Both selection endpoints use the same Pending record and activation guard.
    const selectionId = createHash("sha256").update(`purchase:${requestId}`).digest("hex");
    const member = await this.memberships.select(customerId, packageId, selectionId);
    return { purchase: fromMembership(member), created: true };
  }

  private purchases(customerId: string) {
    return this.firestore
      .collection(customerPurchasesCollection)
      .doc(customerId)
      .collection(purchasesSubcollection);
  }
}

function fromSnapshot(
  snapshot:
    | QueryDocumentSnapshot<DocumentData>
    | DocumentSnapshot<DocumentData>,
): PurchaseRecord {
  const data = snapshot.data();
  if (data === undefined) throw new Error("Purchase record is missing.");
  const purchasedAt = requiredTimestamp(data[fields.purchasedAt], fields.purchasedAt);
  const expiresAt = requiredTimestamp(data[fields.expiresAt], fields.expiresAt);
  return {
    id: snapshot.id,
    customerId: requiredString(data[fields.customerId], fields.customerId),
    packageId: requiredString(data[fields.packageId], fields.packageId),
    packageName: requiredString(data[fields.packageName], fields.packageName),
    pricePaid: requiredPositiveNumber(data[fields.pricePaid], fields.pricePaid),
    durationMonths: requiredPositiveInteger(
      data[fields.durationMonths],
      fields.durationMonths,
    ),
    featureDescription: requiredString(
      data[fields.featureDescription],
      fields.featureDescription,
    ),
    purchasedAt: purchasedAt.toDate().toISOString(),
    expiresAt: expiresAt.toDate().toISOString(),
    requestId: requiredString(data[fields.requestId], fields.requestId),
  };
}

function fromMembership(member: Awaited<ReturnType<FirestorePackageService["select"]>>): PurchaseRecord {
  return {
    id: member.id,
    customerId: member.client_id,
    packageId: member.package.id,
    packageName: member.package.name,
    pricePaid: member.package.price_npr,
    durationMonths: member.package.duration_months ?? Math.ceil(member.package.duration_days / 30),
    ...(member.package.duration_months === undefined ? { durationDays: member.package.duration_days } : {}),
    featureDescription: member.package.features.join("\n"),
    purchasedAt: member.start_at ?? null,
    expiresAt: member.end_at ?? null,
    requestId: member.id,
    status: member.status as PurchaseRecord["status"],
    daysRemaining: member.days_remaining,
  };
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Purchase source ${field} is invalid.`);
  }
  return value;
}

function requiredPositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    throw new Error(`Purchase source ${field} is invalid.`);
  }
  return value;
}

function requiredPositiveNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new Error(`Purchase source ${field} is invalid.`);
  }
  return value;
}

function requiredTimestamp(value: unknown, field: string): Timestamp {
  if (!(value instanceof Timestamp)) {
    throw new Error(`Purchase ${field} is invalid.`);
  }
  return value;
}
