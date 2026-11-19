import {
  CreatePackageResult,
  NewPackage,
  PackageRecord,
  UpdatePackageInput,
} from "./domain";

export interface PackageRepository {
  list(): Promise<PackageRecord[]>;
  listAll(): Promise<PackageRecord[]>;
  createIfAbsent(input: NewPackage): Promise<CreatePackageResult>;
  update(id: string, input: UpdatePackageInput): Promise<PackageRecord>;
  setActiveStatus(id: string, isActive: boolean): Promise<PackageRecord>;
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

export class PackageNotFoundError extends Error {
  constructor() {
    super("Package not found.");
    this.name = "PackageNotFoundError";
  }
}

export class UnconfiguredPackageRepository implements PackageRepository {
  private unavailable(): never {
    throw new PackageStorageNotConfiguredError();
  }

  async list(): Promise<PackageRecord[]> {
    return this.unavailable();
  }

  async listAll(): Promise<PackageRecord[]> {
    return this.unavailable();
  }

  async createIfAbsent(): Promise<CreatePackageResult> {
    return this.unavailable();
  }

  async update(): Promise<PackageRecord> {
    return this.unavailable();
  }

  async setActiveStatus(): Promise<PackageRecord> {
    return this.unavailable();
  }
}
