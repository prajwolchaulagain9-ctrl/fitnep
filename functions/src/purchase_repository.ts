import { CreatePurchaseResult, PurchaseRecord } from "./domain";

export interface PurchaseRepository {
  getLatestForCustomer(customerId: string): Promise<PurchaseRecord | null>;
  purchasePackage(
    customerId: string,
    packageId: string,
    requestId: string,
  ): Promise<CreatePurchaseResult>;
}

export class PurchaseStorageNotConfiguredError extends Error {
  constructor() {
    super("Purchase storage is not configured.");
    this.name = "PurchaseStorageNotConfiguredError";
  }
}

export class PurchaseRequestConflictError extends Error {
  constructor() {
    super("This purchase request identifier is already in use.");
    this.name = "PurchaseRequestConflictError";
  }
}

export class PurchasablePackageNotFoundError extends Error {
  constructor() {
    super("The selected package is not available for purchase.");
    this.name = "PurchasablePackageNotFoundError";
  }
}

export class UnconfiguredPurchaseRepository implements PurchaseRepository {
  private unavailable(): never {
    throw new PurchaseStorageNotConfiguredError();
  }

  async getLatestForCustomer(): Promise<PurchaseRecord | null> {
    return this.unavailable();
  }

  async purchasePackage(): Promise<CreatePurchaseResult> {
    return this.unavailable();
  }
}
