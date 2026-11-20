import {
  AuthenticatedUser,
  NewPackage,
  PackageChangeHistoryRecord,
  PackageRecord,
  SetPackageActiveStatusInput,
  UpdatePackageInput,
} from "./domain";
import { PackageRepository } from "./package_repository";

export interface CreatePackageInput {
  name?: unknown;
  durationMonths?: unknown;
  price?: unknown;
  featureDescription?: unknown;
  requestId?: unknown;
}

export interface UpdatePackageServiceInput {
  name?: unknown;
  durationMonths?: unknown;
  price?: unknown;
  featureDescription?: unknown;
}

export class PackageAuthorizationError extends Error {
  constructor() {
    super("Only administrators can manage packages.");
    this.name = "PackageAuthorizationError";
  }
}

export class InvalidPackageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidPackageError";
  }
}

export class PackageService {
  constructor(private readonly repository: PackageRepository) {}

  /** Returns only active packages — used by customer-facing endpoints. */
  list(): Promise<PackageRecord[]> {
    return this.repository.list();
  }

  /** Returns all packages including inactive — used by admin endpoints. */
  listAll(): Promise<PackageRecord[]> {
    return this.repository.listAll();
  }

  listHistory(user: AuthenticatedUser): Promise<PackageChangeHistoryRecord[]> {
    this.requireAdmin(user);
    return this.repository.listHistory();
  }

  async create(
    user: AuthenticatedUser,
    input: CreatePackageInput,
  ): Promise<PackageRecord> {
    this.requireAdmin(user);

    const packageInput: NewPackage = {
      name: requiredText(input.name, "Package name", 100),
      durationMonths: requiredDuration(input.durationMonths),
      price: requiredPrice(input.price),
      featureDescription: requiredText(
        input.featureDescription,
        "Feature description",
        1000,
      ),
      createdBy: user.uid,
      createdByName: actorName(user),
      requestId: requiredRequestId(input.requestId),
    };
    return (await this.repository.createIfAbsent(packageInput)).package;
  }

  async update(
    user: AuthenticatedUser,
    id: string,
    input: UpdatePackageServiceInput,
  ): Promise<PackageRecord> {
    this.requireAdmin(user);
    if (typeof id !== "string" || id.trim().length === 0) {
      throw new InvalidPackageError("Package id is required.");
    }

    const updateInput: UpdatePackageInput = {
      name: requiredText(input.name, "Package name", 100),
      durationMonths: requiredDuration(input.durationMonths),
      price: requiredPrice(input.price),
      featureDescription: requiredText(
        input.featureDescription,
        "Feature description",
        1000,
      ),
      updatedBy: user.uid,
      updatedByName: actorName(user),
    };
    return this.repository.update(id.trim(), updateInput);
  }

  async setActiveStatus(
    user: AuthenticatedUser,
    id: string,
    isActive: boolean,
  ): Promise<PackageRecord> {
    this.requireAdmin(user);
    if (typeof id !== "string" || id.trim().length === 0) {
      throw new InvalidPackageError("Package id is required.");
    }
    const statusInput: SetPackageActiveStatusInput = {
      isActive,
      updatedBy: user.uid,
      updatedByName: actorName(user),
    };
    return this.repository.setActiveStatus(id.trim(), statusInput);
  }

  private requireAdmin(user: AuthenticatedUser): void {
    if (user.role !== "admin") throw new PackageAuthorizationError();
  }
}

function actorName(user: AuthenticatedUser): string {
  const displayName = user.displayName?.trim();
  return displayName === undefined || displayName.length === 0
    ? user.uid
    : displayName;
}

function requiredText(value: unknown, label: string, maxLength: number): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new InvalidPackageError(`${label} is required.`);
  }
  const normalized = value.trim();
  if (normalized.length > maxLength) {
    throw new InvalidPackageError(
      `${label} must be ${maxLength} characters or fewer.`,
    );
  }
  return normalized;
}

function requiredDuration(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value <= 0) {
    throw new InvalidPackageError(
      "Duration must be a positive whole number of months.",
    );
  }
  if (value > 120) {
    throw new InvalidPackageError("Duration cannot exceed 120 months.");
  }
  return value;
}

function requiredPrice(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) {
    throw new InvalidPackageError("Price must be a positive number.");
  }
  if (value > 100000000) {
    throw new InvalidPackageError("Price is too large.");
  }
  return value;
}

function requiredRequestId(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[A-Za-z0-9_-]{8,128}$/.test(value)
  ) {
    throw new InvalidPackageError("Package request identifier is invalid.");
  }
  return value;
}
