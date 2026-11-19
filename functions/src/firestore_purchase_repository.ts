import {
  DocumentData,
  DocumentSnapshot,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import { CreatePurchaseResult, PurchaseRecord } from "./domain";
import {
  PurchasablePackageNotFoundError,
  PurchaseRepository,
  PurchaseRequestConflictError,
} from "./purchase_repository";

const packagesCollection = "packages";
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
  constructor(private readonly firestore: Firestore) {}

  async getLatestForCustomer(
    customerId: string,
  ): Promise<PurchaseRecord | null> {
    const snapshot = await this.purchases(customerId)
      .orderBy(fields.purchasedAt, "desc")
      .limit(1)
      .get();
    const document = snapshot.docs[0];
    return document === undefined ? null : fromSnapshot(document);
  }

  purchasePackage(
    customerId: string,
    packageId: string,
    requestId: string,
  ): Promise<CreatePurchaseResult> {
    const packageReference = this.firestore
      .collection(packagesCollection)
      .doc(packageId);
    const purchaseReference = this.purchases(customerId).doc(requestId);

    return this.firestore.runTransaction(async (transaction) => {
      const [existingPurchase, packageSnapshot] = await Promise.all([
        transaction.get(purchaseReference),
        transaction.get(packageReference),
      ]);

      if (existingPurchase.exists) {
        const existing = fromSnapshot(existingPurchase);
        if (existing.packageId !== packageId) {
          throw new PurchaseRequestConflictError();
        }
        return { purchase: existing, created: false };
      }

      if (!packageSnapshot.exists) {
        throw new PurchasablePackageNotFoundError();
      }
      const packageData = packageSnapshot.data();
      if (
        packageData === undefined ||
        packageData[fields.isActive] === false
      ) {
        throw new PurchasablePackageNotFoundError();
      }

      const purchasedAt = Timestamp.now();
      const durationMonths = requiredPositiveInteger(
        packageData[fields.durationMonths],
        fields.durationMonths,
      );
      const expiresAt = Timestamp.fromDate(
        addCalendarMonths(purchasedAt.toDate(), durationMonths),
      );
      const record: PurchaseRecord = {
        id: purchaseReference.id,
        customerId,
        packageId: packageSnapshot.id,
        packageName: requiredString(packageData.name, "name"),
        pricePaid: requiredPositiveNumber(packageData.price, "price"),
        durationMonths,
        featureDescription: requiredString(
          packageData[fields.featureDescription],
          fields.featureDescription,
        ),
        purchasedAt: purchasedAt.toDate().toISOString(),
        expiresAt: expiresAt.toDate().toISOString(),
        requestId,
      };

      transaction.create(purchaseReference, {
        [fields.customerId]: record.customerId,
        [fields.packageId]: record.packageId,
        [fields.packageName]: record.packageName,
        [fields.pricePaid]: record.pricePaid,
        [fields.durationMonths]: record.durationMonths,
        [fields.featureDescription]: record.featureDescription,
        [fields.purchasedAt]: purchasedAt,
        [fields.expiresAt]: expiresAt,
        [fields.requestId]: record.requestId,
      });
      return { purchase: record, created: true };
    });
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

export function addCalendarMonths(date: Date, months: number): Date {
  const targetMonth = date.getUTCMonth() + months;
  const targetYear = date.getUTCFullYear() + Math.floor(targetMonth / 12);
  const normalizedMonth = ((targetMonth % 12) + 12) % 12;
  const lastDay = new Date(Date.UTC(targetYear, normalizedMonth + 1, 0)).getUTCDate();
  return new Date(Date.UTC(
    targetYear,
    normalizedMonth,
    Math.min(date.getUTCDate(), lastDay),
    date.getUTCHours(),
    date.getUTCMinutes(),
    date.getUTCSeconds(),
    date.getUTCMilliseconds(),
  ));
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
