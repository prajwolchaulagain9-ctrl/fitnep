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
  PackageChangeHistoryRecord,
  PackageHistoryAction,
  packageHistoryActions,
  PackageHistoryValues,
  PackageRecord,
  SetPackageActiveStatusInput,
  UpdatePackageInput,
} from "./domain";
import {
  PackageNotFoundError,
  PackageRepository,
  PackageRequestConflictError,
} from "./package_repository";

const collectionName = "packages";
const historyCollectionName = "package_change_history";
const maxListSize = 250;
const fields = {
  durationMonths: "duration_months",
  featureDescription: "feature_description",
  isActive: "is_active",
  createdAt: "created_at",
  updatedAt: "updated_at",
  createdBy: "created_by",
  createdByName: "created_by_name",
  updatedBy: "updated_by",
  updatedByName: "updated_by_name",
  requestId: "request_id",
} as const;
const historyFields = {
  packageId: "package_id",
  packageName: "package_name",
  adminId: "admin_id",
  adminName: "admin_name",
  previousValues: "previous_values",
  newValues: "new_values",
  changedAt: "changed_at",
} as const;

export class FirestorePackageRepository implements PackageRepository {
  constructor(private readonly firestore: Firestore) {}

  /** Lists only active packages — for customers. */
  async list(): Promise<PackageRecord[]> {
    const snapshot = await this.collection
      .where(fields.isActive, "==", true)
      .orderBy(fields.createdAt, "desc")
      .limit(maxListSize)
      .get();
    return snapshot.docs.map(fromSnapshot);
  }

  /** Lists all packages regardless of status — for admins. */
  async listAll(): Promise<PackageRecord[]> {
    const snapshot = await this.collection
      .orderBy(fields.createdAt, "desc")
      .limit(maxListSize)
      .get();
    return snapshot.docs.map(fromSnapshot);
  }

  async listHistory(): Promise<PackageChangeHistoryRecord[]> {
    const snapshot = await this.historyCollection
      .orderBy(historyFields.changedAt, "desc")
      .limit(maxListSize)
      .get();
    return snapshot.docs.map(fromHistorySnapshot);
  }

  createIfAbsent(input: NewPackage): Promise<CreatePackageResult> {
    const reference = this.collection.doc(input.requestId);
    const historyReference = this.historyCollection.doc(
      `created_${input.requestId}`,
    );
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
        isActive: true,
        createdAt: createdAt.toDate().toISOString(),
      };
      transaction.create(reference, {
        name: record.name,
        [fields.durationMonths]: record.durationMonths,
        price: record.price,
        [fields.featureDescription]: record.featureDescription,
        [fields.isActive]: true,
        [fields.createdAt]: createdAt,
        [fields.createdBy]: record.createdBy,
        [fields.createdByName]: input.createdByName,
        [fields.requestId]: record.requestId,
      });
      transaction.create(historyReference, {
        [historyFields.packageId]: record.id,
        [historyFields.packageName]: record.name,
        [historyFields.adminId]: input.createdBy,
        [historyFields.adminName]: input.createdByName,
        action: "created",
        [historyFields.previousValues]: null,
        [historyFields.newValues]: toStoredValues(fullPackageValues(record)),
        [historyFields.changedAt]: createdAt,
      });
      return { package: record, created: true };
    });
  }

  async update(id: string, input: UpdatePackageInput): Promise<PackageRecord> {
    const reference = this.collection.doc(id);
    const historyReference = this.historyCollection.doc();
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw new PackageNotFoundError();

      const existing = fromSnapshot(snapshot);
      const changes = changedPackageValues(existing, input);
      if (Object.keys(changes.newValues).length === 0) return existing;

      const updatedAt = Timestamp.now();
      transaction.update(reference, {
        name: input.name,
        [fields.durationMonths]: input.durationMonths,
        price: input.price,
        [fields.featureDescription]: input.featureDescription,
        [fields.updatedAt]: updatedAt,
        [fields.updatedBy]: input.updatedBy,
        [fields.updatedByName]: input.updatedByName,
      });
      const updated = {
        ...existing,
        name: input.name,
        durationMonths: input.durationMonths,
        price: input.price,
        featureDescription: input.featureDescription,
      };
      transaction.create(historyReference, {
        [historyFields.packageId]: updated.id,
        [historyFields.packageName]: updated.name,
        [historyFields.adminId]: input.updatedBy,
        [historyFields.adminName]: input.updatedByName,
        action: "updated",
        [historyFields.previousValues]: toStoredValues(changes.previousValues),
        [historyFields.newValues]: toStoredValues(changes.newValues),
        [historyFields.changedAt]: updatedAt,
      });
      return updated;
    });
  }

  async setActiveStatus(
    id: string,
    input: SetPackageActiveStatusInput,
  ): Promise<PackageRecord> {
    const reference = this.collection.doc(id);
    const historyReference = this.historyCollection.doc();
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(reference);
      if (!snapshot.exists) throw new PackageNotFoundError();

      const existing = fromSnapshot(snapshot);
      if (existing.isActive === input.isActive) return existing;

      const updatedAt = Timestamp.now();
      transaction.update(reference, {
        [fields.isActive]: input.isActive,
        [fields.updatedAt]: updatedAt,
        [fields.updatedBy]: input.updatedBy,
        [fields.updatedByName]: input.updatedByName,
      });
      const updated = { ...existing, isActive: input.isActive };
      transaction.create(historyReference, {
        [historyFields.packageId]: updated.id,
        [historyFields.packageName]: updated.name,
        [historyFields.adminId]: input.updatedBy,
        [historyFields.adminName]: input.updatedByName,
        action: input.isActive ? "activated" : "deactivated",
        [historyFields.previousValues]: { [fields.isActive]: existing.isActive },
        [historyFields.newValues]: { [fields.isActive]: input.isActive },
        [historyFields.changedAt]: updatedAt,
      });
      return updated;
    });
  }

  private get collection() {
    return this.firestore.collection(collectionName);
  }

  private get historyCollection() {
    return this.firestore.collection(historyCollectionName);
  }
}

function fromHistorySnapshot(
  snapshot: QueryDocumentSnapshot<DocumentData>,
): PackageChangeHistoryRecord {
  const data = snapshot.data();
  const changedAt = data[historyFields.changedAt];
  if (!(changedAt instanceof Timestamp)) {
    throw new Error("Package history changed_at is invalid.");
  }
  const action = data.action;
  if (
    typeof action !== "string" ||
    !packageHistoryActions.includes(action as PackageHistoryAction)
  ) {
    throw new Error("Package history action is invalid.");
  }
  return {
    id: snapshot.id,
    packageId: requiredString(
      data[historyFields.packageId],
      historyFields.packageId,
    ),
    packageName: requiredString(
      data[historyFields.packageName],
      historyFields.packageName,
    ),
    adminId: requiredString(data[historyFields.adminId], historyFields.adminId),
    adminName: requiredString(
      data[historyFields.adminName],
      historyFields.adminName,
    ),
    action: action as PackageHistoryAction,
    previousValues: data[historyFields.previousValues] === null
      ? null
      : fromStoredValues(data[historyFields.previousValues]),
    newValues: fromStoredValues(data[historyFields.newValues]),
    changedAt: changedAt.toDate().toISOString(),
  };
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

  // isActive defaults to true for documents created before the field existed.
  const isActive = typeof data[fields.isActive] === "boolean"
    ? data[fields.isActive]
    : true;

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
    isActive,
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

function fullPackageValues(record: PackageRecord): PackageHistoryValues {
  return {
    name: record.name,
    durationMonths: record.durationMonths,
    price: record.price,
    featureDescription: record.featureDescription,
    isActive: record.isActive,
  };
}

function changedPackageValues(
  existing: PackageRecord,
  input: UpdatePackageInput,
): {
  previousValues: PackageHistoryValues;
  newValues: PackageHistoryValues;
} {
  const previousValues: PackageHistoryValues = {};
  const newValues: PackageHistoryValues = {};
  if (existing.name !== input.name) {
    previousValues.name = existing.name;
    newValues.name = input.name;
  }
  if (existing.durationMonths !== input.durationMonths) {
    previousValues.durationMonths = existing.durationMonths;
    newValues.durationMonths = input.durationMonths;
  }
  if (existing.price !== input.price) {
    previousValues.price = existing.price;
    newValues.price = input.price;
  }
  if (existing.featureDescription !== input.featureDescription) {
    previousValues.featureDescription = existing.featureDescription;
    newValues.featureDescription = input.featureDescription;
  }
  return { previousValues, newValues };
}

function toStoredValues(values: PackageHistoryValues): Record<string, unknown> {
  const stored: Record<string, unknown> = {};
  if (values.name !== undefined) stored.name = values.name;
  if (values.durationMonths !== undefined) {
    stored[fields.durationMonths] = values.durationMonths;
  }
  if (values.price !== undefined) stored.price = values.price;
  if (values.featureDescription !== undefined) {
    stored[fields.featureDescription] = values.featureDescription;
  }
  if (values.isActive !== undefined) {
    stored[fields.isActive] = values.isActive;
  }
  return stored;
}

function fromStoredValues(value: unknown): PackageHistoryValues {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("Package history values are invalid.");
  }
  const stored = value as Record<string, unknown>;
  const values: PackageHistoryValues = {};
  if (stored.name !== undefined) {
    values.name = requiredString(stored.name, "history name");
  }
  if (stored[fields.durationMonths] !== undefined) {
    values.durationMonths = requiredPositiveInteger(
      stored[fields.durationMonths],
      `history ${fields.durationMonths}`,
    );
  }
  if (stored.price !== undefined) {
    values.price = requiredPositiveNumber(stored.price, "history price");
  }
  if (stored[fields.featureDescription] !== undefined) {
    values.featureDescription = requiredString(
      stored[fields.featureDescription],
      `history ${fields.featureDescription}`,
    );
  }
  if (stored[fields.isActive] !== undefined) {
    const isActive = stored[fields.isActive];
    if (typeof isActive !== "boolean") {
      throw new Error(`Package history ${fields.isActive} is invalid.`);
    }
    values.isActive = isActive;
  }
  return values;
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
