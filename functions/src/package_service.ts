import { createHash } from "node:crypto";
import { Firestore } from "firebase-admin/firestore";
import { AuthenticatedUser } from "./domain";

const day = 86_400_000;

export class PackageError extends Error {
  constructor(readonly statusCode: number, message: string) { super(message); }
}

export interface PackageRecord {
  id: string;
  name: string;
  duration_days: number;
  price_npr: number;
  features: string[];
}

export interface MembershipRecord {
  id: string;
  client_id: string;
  package: PackageRecord;
  status: "pending" | "active";
  created_at: string;
  start_at?: string;
  end_at?: string;
  payment_id?: string;
}

// Every selection/activation touches the same client guard. Firestore retries
// conflicting transactions, including concurrent activations of different IDs.
export class FirestorePackageService {
  constructor(private readonly db: Firestore, private readonly now = () => new Date()) {}

  async catalog(): Promise<PackageRecord[]> {
    const snapshot = await this.db.collection("package_catalog").where("active", "==", true).get();
    return snapshot.docs.map(doc => parsePackage(doc.id, doc.data())).sort((a, b) => a.price_npr - b.price_npr);
  }

  async memberships(uid: string) {
    const snapshot = await this.db.collection("package_memberships").where("client_id", "==", uid).get();
    return snapshot.docs.map(doc => this.toApi(doc.data() as MembershipRecord))
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
  }

  async pendingMemberships() {
    const snapshot = await this.db.collection("package_memberships").where("status", "==", "pending").get();
    return snapshot.docs.map(doc => this.toApi(doc.data() as MembershipRecord))
      .sort((a, b) => a.created_at.localeCompare(b.created_at));
  }

  async verifyManually(actor: AuthenticatedUser, membershipId: string, reference: string) {
    if (actor.role !== "admin") throw new PackageError(403, "Only an administrator can verify a payment.");
    if (!/^[a-f0-9]{64}$/.test(membershipId) || reference.trim().length < 3 || reference.length > 200) {
      throw new PackageError(400, "A valid membership and verification reference are required.");
    }
    return this.activate(`manual_${membershipId}`, { membershipId, adminId: actor.uid, reference: reference.trim() });
  }

  async select(uid: string, packageId: string, requestId: string) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(packageId) || !/^[A-Za-z0-9_-]{16,128}$/.test(requestId)) {
      throw new PackageError(400, "A valid package and request ID are required.");
    }
    const id = createHash("sha256").update(`${uid}:${requestId}`).digest("hex");
    const membershipRef = this.db.collection("package_memberships").doc(id);
    const catalogRef = this.db.collection("package_catalog").doc(packageId);
    const guardRef = this.db.collection("package_membership_guards").doc(uid);
    const record = await this.db.runTransaction(async tx => {
      const [existing, catalog, guard] = await Promise.all([tx.get(membershipRef), tx.get(catalogRef), tx.get(guardRef)]);
      if (existing.exists) {
        const member = existing.data() as MembershipRecord;
        if (member.client_id !== uid || member.package.id !== packageId) {
          throw new PackageError(409, "This request ID was already used for another selection.");
        }
        return member;
      }
      if (!catalog.exists || catalog.get("active") !== true) {
        throw new PackageError(409, "This package is no longer available. Refresh the catalog.");
      }
      const item = parsePackage(catalog.id, catalog.data()!);
      const pendingId = guard.get("pending_id") as string | undefined;
      if (pendingId) {
        const pending = await tx.get(this.db.collection("package_memberships").doc(pendingId));
        if (pending.exists && pending.get("status") === "pending") {
          const member = pending.data() as MembershipRecord;
          if (member.package.id === packageId) return member;
          throw new PackageError(409, "You already have a package awaiting payment verification.");
        }
      }
      const member: MembershipRecord = { id, client_id: uid, package: item, status: "pending", created_at: this.now().toISOString() };
      tx.create(membershipRef, member);
      tx.set(guardRef, { pending_id: id, updated_at: member.created_at }, { merge: true });
      return member;
    });
    return this.toApi(record);
  }

  // Called exclusively by trusted payment processing, never by a mobile route.
  async activateVerifiedPayment(paymentId: string) {
    return this.activate(paymentId);
  }

  private async activate(paymentId: string, manual?: { membershipId: string; adminId: string; reference: string }) {
    const paymentRef = this.db.collection("payments").doc(paymentId);
    return this.db.runTransaction(async tx => {
      const payment = await tx.get(paymentRef);
      let data = payment.data();
      const membershipId = manual?.membershipId ?? data?.membership_id;
      if (typeof membershipId !== "string" || !/^[a-f0-9]{64}$/.test(membershipId)) {
        throw new PackageError(400, "Payment must reference a package membership.");
      }
      const membershipRef = this.db.collection("package_memberships").doc(membershipId);
      const snapshot = await tx.get(membershipRef);
      if (!snapshot.exists) throw new PackageError(404, "Membership not found.");
      const member = snapshot.data() as MembershipRecord;
      parsePackage(member.package.id, member.package as unknown as Record<string, unknown>);
      if (manual) {
        if (data && (data.method !== "manual" || data.membership_id !== membershipId || data.verification_reference !== manual.reference)) {
          throw new PackageError(409, "This membership already has a different manual verification record.");
        }
        data ??= {
          membership_id: membershipId, recipient_id: member.client_id,
          amount_npr: member.package.price_npr, currency: "NPR", status: "confirmed", verified: true,
          method: "manual", verified_by: manual.adminId, verification_reference: manual.reference,
          verified_at: this.now().toISOString(),
        };
      }
      if (!data || data.verified !== true || !["paid", "confirmed", "succeeded"].includes(data.status)) {
        throw new PackageError(409, "Payment has not been verified.");
      }
      if (data.recipient_id !== member.client_id || data.amount_npr !== member.package.price_npr || data.currency !== "NPR") {
        throw new PackageError(409, "Payment does not match the selected package.");
      }
      if (member.status === "active" && member.payment_id === paymentId) return this.toApi(member);
      if (member.status !== "pending") throw new PackageError(409, "Membership is already activated.");
      const guardRef = this.db.collection("package_membership_guards").doc(member.client_id);
      const [guard, active] = await Promise.all([
        tx.get(guardRef),
        tx.get(this.db.collection("package_memberships").where("client_id", "==", member.client_id).where("status", "==", "active")),
      ]);
      const start = data.membership_start_at === undefined ? this.now() : new Date(data.membership_start_at);
      if (!Number.isFinite(start.getTime()) || (data.membership_start_at !== undefined && start.getTime() < this.now().getTime())) {
        throw new PackageError(400, "The membership start must be a valid current or future date.");
      }
      const end = new Date(start.getTime() + member.package.duration_days * day);
      const overlaps = active.docs.some(doc => {
        const other = doc.data() as MembershipRecord;
        if (!Number.isFinite(Date.parse(other.start_at!)) || !Number.isFinite(Date.parse(other.end_at!)) || Date.parse(other.end_at!) <= Date.parse(other.start_at!)) {
          throw new PackageError(503, "An existing membership needs attention before activation.");
        }
        return start.getTime() < Date.parse(other.end_at!) && Date.parse(other.start_at!) < end.getTime();
      });
      if (overlaps) throw new PackageError(409, "An active package already covers these dates.");
      const activated: MembershipRecord = { ...member, status: "active", start_at: start.toISOString(), end_at: end.toISOString(), payment_id: paymentId };
      if (manual && !payment.exists) tx.create(paymentRef, data);
      tx.set(membershipRef, activated);
      tx.set(guardRef, { pending_id: guard.get("pending_id") === member.id ? null : (guard.get("pending_id") ?? null), updated_at: this.now().toISOString() }, { merge: true });
      return this.toApi(activated);
    });
  }

  private toApi(member: MembershipRecord) {
    const now = this.now().getTime();
    const status = member.status === "pending" ? "pending" : now >= Date.parse(member.end_at!) ? "expired" : now < Date.parse(member.start_at!) ? "scheduled" : "active";
    return { ...member, status, days_remaining: status === "active" ? Math.max(0, Math.ceil((Date.parse(member.end_at!) - now) / day)) : status === "scheduled" ? member.package.duration_days : 0 };
  }
}

function parsePackage(id: string, data: Record<string, unknown>): PackageRecord {
  if (typeof data.name !== "string" || !data.name.trim() || data.name.length > 100 ||
      !Number.isSafeInteger(data.duration_days) || Number(data.duration_days) < 1 || Number(data.duration_days) > 3650 ||
      !Number.isSafeInteger(data.price_npr) || Number(data.price_npr) < 1 || Number(data.price_npr) > 1_000_000_000 ||
      !Array.isArray(data.features) || data.features.length === 0 || data.features.length > 100 ||
      !data.features.every(feature => typeof feature === "string" && feature.trim().length > 0 && feature.length <= 500)) {
    throw new PackageError(503, "The package catalog needs attention. Please try again later.");
  }
  return { id, name: data.name.trim(), duration_days: Number(data.duration_days), price_npr: Number(data.price_npr), features: data.features as string[] };
}
