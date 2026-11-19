import {
  AuthenticatedUser,
  NewPackage,
  PackageRecord,
} from "./domain";
import { PackageRepository } from "./package_repository";

export interface CreatePackageInput {
  name?: unknown;
  durationMonths?: unknown;
  price?: unknown;
  featureDescription?: unknown;
  requestId?: unknown;
}

export class PackageAuthorizationError extends Error {
  constructor() {
    super("Only administrators can create packages.");
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

  list(): Promise<PackageRecord[]> {
    return this.repository.list();
  }

  async create(
    user: AuthenticatedUser,
    input: CreatePackageInput,
  ): Promise<PackageRecord> {
    if (user.role !== "admin") throw new PackageAuthorizationError();

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
      requestId: requiredRequestId(input.requestId),
    };
    return (await this.repository.createIfAbsent(packageInput)).package;
  }
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
