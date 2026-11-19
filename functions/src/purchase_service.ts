import { AuthenticatedUser, PurchaseRecord } from "./domain";
import { PurchaseRepository } from "./purchase_repository";

export interface CreatePurchaseInput {
  packageId?: unknown;
  requestId?: unknown;
}

export class PurchaseAuthorizationError extends Error {
  constructor() {
    super("Only customer accounts can purchase packages.");
    this.name = "PurchaseAuthorizationError";
  }
}

export class InvalidPurchaseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidPurchaseError";
  }
}

export class PurchaseService {
  constructor(private readonly repository: PurchaseRepository) {}

  getCurrent(user: AuthenticatedUser): Promise<PurchaseRecord | null> {
    this.requireClient(user);
    return this.repository.getLatestForCustomer(user.uid);
  }

  async create(
    user: AuthenticatedUser,
    input: CreatePurchaseInput,
  ): Promise<PurchaseRecord> {
    this.requireClient(user);
    const packageId = requiredId(input.packageId, "Package id");
    const requestId = requiredRequestId(input.requestId);
    return (
      await this.repository.purchasePackage(user.uid, packageId, requestId)
    ).purchase;
  }

  private requireClient(user: AuthenticatedUser): void {
    if (user.role !== "client") throw new PurchaseAuthorizationError();
  }
}

function requiredId(value: unknown, label: string): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{1,200}$/.test(value)) {
    throw new InvalidPurchaseError(`${label} is invalid.`);
  }
  return value;
}

function requiredRequestId(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{8,128}$/.test(value)) {
    throw new InvalidPurchaseError("Purchase request identifier is invalid.");
  }
  return value;
}
