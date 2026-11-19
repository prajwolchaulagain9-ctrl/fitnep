import {
  CreatePackageResult,
  NewPackage,
  PackageRecord,
} from "./domain";

export interface PackageRepository {
  list(): Promise<PackageRecord[]>;
  createIfAbsent(input: NewPackage): Promise<CreatePackageResult>;
}

export class PackageStorageNotConfiguredError extends Error {
  constructor() {
    super("Package storage is not configured.");
    this.name = "PackageStorageNotConfiguredError";
  }
}

export class PackageRequestConflictError extends Error {
  constructor() {
    super("This package request identifier is already in use.");
    this.name = "PackageRequestConflictError";
  }
}

export class UnconfiguredPackageRepository implements PackageRepository {
  private unavailable(): never {
    throw new PackageStorageNotConfiguredError();
  }

  async list(): Promise<PackageRecord[]> {
    return this.unavailable();
  }

  async createIfAbsent(): Promise<CreatePackageResult> {
    return this.unavailable();
  }
}
