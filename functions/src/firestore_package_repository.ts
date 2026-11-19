import {
  DocumentData,
  DocumentSnapshot,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";

import {
  CreatePackageResult,
  NewPackage,
  PackageRecord,
} from "./domain";
import {
  PackageRepository,
  PackageRequestConflictError,
} from "./package_repository";

const collectionName = "packages";
const maxListSize = 250;
const fields = {
  durationMonths: "duration_months",
  featureDescription: "feature_description",
  createdAt: "created_at",
  createdBy: "created_by",
  requestId: "request_id",
} as const;

export class FirestorePackageRepository implements PackageRepository {
  constructor(private readonly firestore: Firestore) {}

  async list(): Promise<PackageRecord[]> {
    const snapshot = await this.collection
      .orderBy(fields.createdAt, "desc")
      .limit(maxListSize)
      .get();
    return snapshot.docs.map(fromSnapshot);
  }

  createIfAbsent(input: NewPackage): Promise<CreatePackageResult> {
    const reference = this.collection.doc(input.requestId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (snapshot.exists) {
        const existing = fromSnapshot(snapshot);
        if (!matchesInput(existing, input)) {
          throw new PackageRequestConflictError();
        }
        return { package: existing, created: false };
      }

      const createdAt = Timestamp.now();
      const record: PackageRecord = {
        id: reference.id,
        ...input,
        createdAt: createdAt.toDate().toISOString(),
      };
      transaction.create(reference, {
        name: record.name,
        [fields.durationMonths]: record.durationMonths,
        price: record.price,
        [fields.featureDescription]: record.featureDescription,
        [fields.createdAt]: createdAt,
        [fields.createdBy]: record.createdBy,
        [fields.requestId]: record.requestId,
      });
      return { package: record, created: true };
    });
  }

  private get collection() {
    return this.firestore.collection(collectionName);
  }
}

function fromSnapshot(
  snapshot:
    | QueryDocumentSnapshot<DocumentData>
    | DocumentSnapshot<DocumentData>,
): PackageRecord {
  const data = snapshot.data();
  if (data === undefined) throw new Error("Package record is missing.");
  const createdAt = data[fields.createdAt];
  if (!(createdAt instanceof Timestamp)) {
    throw new Error("Package created_at is invalid.");
  }

  return {
    id: snapshot.id,
    name: requiredString(data.name, "name"),
    durationMonths: requiredPositiveInteger(
      data[fields.durationMonths],
      fields.durationMonths,
    ),
    price: requiredPositiveNumber(data.price, "price"),
    featureDescription: requiredString(
      data[fields.featureDescription],
      fields.featureDescription,
    ),
    createdAt: createdAt.toDate().toISOString(),
    createdBy: requiredString(data[fields.createdBy], fields.createdBy),
    requestId: requiredString(data[fields.requestId], fields.requestId),
  };
}

function matchesInput(record: PackageRecord, input: NewPackage): boolean {
  return record.name === input.name &&
    record.durationMonths === input.durationMonths &&
    record.price === input.price &&
    record.featureDescription === input.featureDescription &&
    record.createdBy === input.createdBy &&
    record.requestId === input.requestId;
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Package ${field} is invalid.`);
  }
  return value;
}

function requiredPositiveInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    throw new Error(`Package ${field} is invalid.`);
  }
  return value;
}

function requiredPositiveNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new Error(`Package ${field} is invalid.`);
  }
  return value;
}
