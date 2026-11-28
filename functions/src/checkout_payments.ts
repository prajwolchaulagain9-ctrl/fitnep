import { createHash } from "node:crypto";
import { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { accountFrom, accountMatchesActor } from "./account_service";
import { AuditWriter } from "./audit";
import { hasPermission, PermissionDeniedError } from "./authorization_policy";
import { isObject } from "./client_intake_answers";
import { isPhotoMimeType, PhotoMimeType, PrivatePhotoStorage } from "./cloudinary_photo_storage";
import { AuthenticatedUser } from "./domain";
import { onboardingReady } from "./onboarding";
import { FirestorePackageService, MembershipRecord, PackageError, PackageRecord } from "./package_membership_service";
import { maxPhotoBytes, photoContentType } from "./private_records";

const workflow = "package_checkout";
const requestIdentifier = /^[A-Za-z0-9_-]{16,128}$/;
const documentIdentifier = /^[a-f0-9]{64}$/;
const sha256 = (value: string | Buffer) => createHash("sha256").update(value).digest("hex");

interface Payment {
  workflow: typeof workflow;
  id: string;
  membership_id: string;
  recipient_id: string;
  client_id: string;
  client_name: string;
  package: PackageRecord;
  amount_npr: number;
  currency: "NPR";
  reference: string;
  qr_payload: string;
  revision: number;
  status: "pending" | "verified" | "rejected";
  verified: boolean;
  created_at: string;
  proof_digest: string;
  proof_type: PhotoMimeType;
  reviewed_at?: string;
  reviewed_by?: string;
  reviewed_by_name?: string;
  rejection_reason?: string;
}

export class CheckoutPayments {
  constructor(private readonly db: Firestore, private readonly memberships: FirestorePackageService,
    private readonly audit: AuditWriter, private readonly photoStorage?: PrivatePhotoStorage) {}

  async checkout(actor: AuthenticatedUser, requestedId?: unknown) {
    if (requestedId !== undefined) verifyId(requestedId);
    return this.db.runTransaction(async tx => {
      await this.assertClient(actor, tx);
      const guard = await tx.get(this.db.doc(`package_membership_guards/${actor.uid}`));
      const id = guard.get("pending_id");
      if (typeof id !== "string") return null;
      if (requestedId !== undefined && requestedId !== id) return null;
      const member = (await tx.get(this.db.doc(`package_memberships/${id}`))).data() as MembershipRecord | undefined;
      if (!member || member.client_id !== actor.uid || member.status !== "pending") return null;
      const payment = member.checkout_payment_id
        ? (await tx.get(this.paymentRef(member.checkout_payment_id))).data() as Payment : undefined;
      const revision = (member.checkout_revision ?? 0) + 1;
      const terms = payment?.status === "pending"
        ? { reference: payment.reference, qr_payload: payment.qr_payload, revision: payment.revision }
        : checkoutTerms(member, revision);
      return { membership_id: id, package: member.package, amount_npr: member.package.price_npr, currency: "NPR", ...terms,
        ...(payment ? { payment_id: payment.id, payment_status: payment.status } : {}) };
    });
  }

  async submit(actor: AuthenticatedUser, id: string, input: unknown, correlationId: string) {
    verifyId(id);
    if (!isObject(input) || Object.keys(input).some(key => ![
      "proof_base64", "content_type", "request_id", "expected_client_id", "expected_reference", "revision",
    ].includes(key))) throw new PackageError(400, "Only a payment proof photo may be submitted.");
    if (input.expected_client_id !== undefined && input.expected_client_id !== actor.uid) throw new PermissionDeniedError();
    const { request_id: requestId } = input;
    if (requestId !== undefined && (typeof requestId !== "string" || !requestIdentifier.test(requestId))) {
      throw new PackageError(400, "Invalid payment request ID.");
    }
    const { bytes, contentType } = parsePhoto(input);
    const digest = sha256(bytes);
    const paymentId = sha256(JSON.stringify([id, requestId ?? digest]));
    const paymentRef = this.paymentRef(paymentId);
    const memberRef = this.db.doc(`package_memberships/${id}`);
    const guardRef = this.db.doc(`package_membership_guards/${actor.uid}`);
    const digestRef = this.db.doc(`payment_proof_digests/${digest}`);
    const uploadRef = this.db.doc(`payment_proof_uploads/${id}`);

    const stage = (finish: boolean) => this.db.runTransaction(async tx => {
      const account = await this.assertClient(actor, tx);
      const [memberDoc, guard, saved, duplicate, upload] = await Promise.all([
        tx.get(memberRef), tx.get(guardRef), tx.get(paymentRef), tx.get(digestRef), tx.get(uploadRef),
      ]);
      const member = memberDoc.data() as MembershipRecord | undefined;
      if (!member || member.client_id !== actor.uid) throw new PackageError(404, "Membership not found.");
      const existing = saved.data() as Payment | undefined;
      if (existing) {
        if (existing.proof_digest !== digest || existing.membership_id !== id || existing.recipient_id !== actor.uid ||
            (input.expected_reference !== undefined && existing.reference !== input.expected_reference)) {
          throw new PackageError(409, "This payment request was already used.");
        }
        return existing;
      }
      if (duplicate.exists) throw new PackageError(409, "This payment proof photo has already been submitted.");
      if (member.status !== "pending" || guard.get("pending_id") !== id) {
        throw new PackageError(409, "This package is no longer awaiting payment.");
      }
      if (member.checkout_payment_id) {
        const previous = await tx.get(this.paymentRef(member.checkout_payment_id));
        if (previous.get("status") !== "rejected") throw new PackageError(409, "Your payment is already awaiting review.");
      }
      const revision = (member.checkout_revision ?? 0) + 1;
      const terms = checkoutTerms(member, revision);
      if ((input.revision !== undefined && input.revision !== revision) ||
          (input.expected_reference !== undefined && input.expected_reference !== terms.reference)) {
        throw new PackageError(409, "The checkout changed. Refresh it before submitting new proof.");
      }
      const sameUpload = upload.get("payment_id") === paymentId && upload.get("proof_digest") === digest;
      if (upload.get("payment_id") === paymentId && !sameUpload) {
        throw new PackageError(409, "This payment request was already used.");
      }
      if (finish && !sameUpload) throw new PackageError(409, "The checkout changed. Retry the proof upload.");
      if (!sameUpload && upload.exists && upload.get("expires_at")?.toMillis() > Date.now()) {
        throw new PackageError(409, "Another photo is being uploaded for this checkout.");
      }
      if (!finish) {
        if (!this.photoStorage) throw unavailable();
        tx.set(uploadRef, { payment_id: paymentId, proof_digest: digest, expires_at: Timestamp.fromMillis(Date.now() + 120_000) });
        return undefined;
      }
      const payment: Payment = {
        workflow, id: paymentId, membership_id: id, recipient_id: actor.uid, client_id: actor.uid,
        client_name: account.full_name || actor.displayName || actor.uid,
        package: member.package, amount_npr: member.package.price_npr, currency: "NPR", ...terms,
        created_at: new Date().toISOString(), status: "pending", verified: false, proof_digest: digest, proof_type: contentType,
      };
      tx.create(paymentRef, payment);
      tx.create(digestRef, { payment_id: paymentId });
      tx.update(memberRef, { checkout_payment_id: paymentId, checkout_revision: revision });
      tx.delete(uploadRef);
      this.audit.appendInTransaction(tx, {
        actor, action: "payment.submitted", targetType: "payment", targetId: paymentId, clientId: actor.uid,
        outcome: "succeeded", status: "pending", version: revision, operationId: paymentId, correlationId,
      });
      return payment;
    });
    const existing = await stage(false);
    if (existing) return summary(existing);
    const storage = this.storage();
    const photoId = proofStorageId(digest);
    try {
      await storage.write(photoId, bytes, contentType);
    } catch {
      try {
        // An upload may have succeeded before its acknowledgement was lost.
        if (sha256(await storage.read(photoId, contentType)) !== digest) throw unavailable();
      } catch {
        throw unavailable();
      }
    }
    const saved = await stage(true);
    if (!saved) throw unavailable();
    return summary(saved);
  }

  async listOwn(actor: AuthenticatedUser) {
    if (actor.role !== "client") throw new PermissionDeniedError();
    await this.currentAccount(actor);
    return this.listClientPayments(actor.uid);
  }

  async listClientPayments(clientId: string) {
    return this.list(await this.db.collection("payments").where("workflow", "==", workflow)
      .where("recipient_id", "==", clientId).get());
  }

  async listReview(actor: AuthenticatedUser, status: unknown = "pending") {
    await this.assertReviewer(actor);
    if (status !== "pending" && status !== "verified" && status !== "rejected" && status !== "all") {
      throw new PackageError(400, "Invalid payment status.");
    }
    let query = this.db.collection("payments").where("workflow", "==", workflow);
    if (status !== "all") query = query.where("status", "==", status);
    return this.list(await query.get());
  }

  private list(snapshot: FirebaseFirestore.QuerySnapshot) {
    return snapshot.docs.map(doc => summary(doc.data() as Payment)).sort((a, b) => b.created_at.localeCompare(a.created_at));
  }

  async detail(actor: AuthenticatedUser, id: string, reviewerOnly = false) {
    const payment = await this.getPayment(actor, id, reviewerOnly);
    if (!payment) return null;
    const adjustments = await this.paymentRef(id).collection("adjustments").orderBy("created_at").get();
    return { payment: summary(payment), adjustments: adjustments.docs.map(adjustment => adjustment.data()) };
  }

  async proof(actor: AuthenticatedUser, id: string) {
    const payment = await this.getPayment(actor, id);
    if (!payment || !isPhotoMimeType(payment.proof_type)) throw new PackageError(404, "Payment proof not found.");
    const bytes = await this.storage().read(proofStorageId(payment.proof_digest), payment.proof_type);
    if (sha256(bytes) !== payment.proof_digest) throw unavailable();
    return { bytes, contentType: payment.proof_type };
  }

  async decide(actor: AuthenticatedUser, id: string, status: "verified" | "rejected", input: unknown, correlationId: string) {
    const ref = this.paymentRef(id);
    if (!isObject(input) || Object.keys(input).some(key =>
      !["revision", status === "rejected" ? "reason" : "proof_reviewed"].includes(key))) {
      throw new PackageError(400, "Invalid payment decision.");
    }
    if (!Number.isSafeInteger(input.revision) || Number(input.revision) < 1 ||
        (status === "verified" && input.proof_reviewed !== true)) {
      throw new PackageError(400, "Reload the payment and confirm you reviewed its QR code and proof.");
    }
    const reason = status === "rejected" ? requiredReason(input.reason) : undefined;
    return this.db.runTransaction(async tx => {
      const account = await this.assertReviewer(actor, tx);
      const current = (await tx.get(ref)).data() as Payment | undefined;
      if (current?.workflow !== workflow) throw new PackageError(404, "Payment not found.");
      if (input.revision !== current.revision ||
          (current.status !== "pending" && (current.status !== status || current.rejection_reason !== reason))) {
        throw new PackageError(409, "This payment has already been decided. Refresh the review queue.");
      }
      const actorName = account.full_name || actor.displayName || actor.uid;
      const trustedActor = { ...actor, displayName: actorName };
      const decision = { status, verified: status === "verified", reviewed_at: new Date().toISOString(),
        reviewed_by: actor.uid, reviewed_by_name: actorName, ...(status === "verified" ? { proof_reviewed: true } : {}),
        ...(reason ? { rejection_reason: reason } : {}) };
      const member = (await tx.get(this.db.doc(`package_memberships/${current.membership_id}`))).data() as MembershipRecord | undefined;
      if (!member || member.client_id !== current.recipient_id ||
          member.checkout_payment_id !== id || member.checkout_revision !== current.revision) {
        if (current.status === "rejected" && current.status === status) return { payment: summary(current) };
        throw new PackageError(409, "This payment no longer matches the package.");
      }
      const membership = status === "verified"
        ? await this.memberships.activateInTransaction(tx, member, id, { ...current, ...decision }, true)
        : undefined;
      if (current.status === status) return { payment: summary(current), ...(membership ? { membership } : {}) };
      tx.update(ref, decision);
      const action = status === "verified" ? "payment.verified" : "payment.rejected";
      this.audit.appendWithEvent(tx, {
        actor: trustedActor, action, targetType: "payment", targetId: id, clientId: current.recipient_id,
        outcome: "succeeded", status, version: current.revision, operationId: id, correlationId,
      }, action);
      if (membership) this.audit.appendWithEvent(tx, {
        actor: trustedActor, action: "membership.activated", targetType: "membership", targetId: membership.id,
        clientId: current.recipient_id, outcome: "succeeded", status: membership.status, operationId: id, correlationId,
      }, "membership.activated");
      return { payment: summary({ ...current, ...decision }), ...(membership ? { membership } : {}) };
    });
  }

  async adjust(actor: AuthenticatedUser, id: string, input: unknown, correlationId: string) {
    const paymentRef = this.paymentRef(id);
    if (!isObject(input) || Object.keys(input).some(key => !["amount_delta_npr", "reason", "request_id"].includes(key))) {
      throw new PackageError(400, "Invalid payment adjustment.");
    }
    const { amount_delta_npr: delta, request_id: requestId } = input;
    const reason = requiredReason(input.reason);
    if (typeof delta !== "number" || !Number.isFinite(delta) || Math.abs(delta) < 0.01 ||
        Math.abs(delta) > 1_000_000_000 || Math.round(delta * 100) / 100 !== delta ||
        typeof requestId !== "string" || !requestIdentifier.test(requestId)) {
      throw new PackageError(400, "Supply a nonzero NPR adjustment (up to two decimal places) and a request ID.");
    }
    const ref = paymentRef.collection("adjustments").doc(requestId);
    return this.db.runTransaction(async tx => {
      const account = await this.currentAccount(actor, tx);
      if (account.role !== "admin") throw new PermissionDeniedError();
      const [payment, existing] = await Promise.all([tx.get(paymentRef), tx.get(ref)]);
      if (payment.get("workflow") !== workflow) throw new PackageError(404, "Payment not found.");
      if (payment.get("status") !== "verified") throw new PackageError(409, "Only verified payments may have an adjustment.");
      if (existing.exists) {
        if (existing.get("reason") !== reason || existing.get("amount_delta_npr") !== delta || existing.get("created_by") !== actor.uid) {
          throw new PackageError(409, "This adjustment request was already used.");
        }
        return existing.data();
      }
      const name = account.full_name || actor.displayName || actor.uid;
      const adjustment = { id: ref.id, payment_id: id, amount_delta_npr: delta, reason, created_at: new Date().toISOString(),
        created_by: actor.uid, created_by_name: name };
      tx.create(ref, adjustment);
      this.audit.appendInTransaction(tx, {
        actor: { ...actor, displayName: name }, action: "payment.adjusted", targetType: "payment", targetId: id,
        clientId: payment.get("recipient_id"), status: "adjusted", outcome: "succeeded", operationId: requestId, correlationId,
      });
      return adjustment;
    });
  }

  private async getPayment(actor: AuthenticatedUser, id: string, reviewerOnly = false) {
    if (!documentIdentifier.test(id)) return null;
    const payment = (await this.paymentRef(id).get()).data() as Payment | undefined;
    if (payment?.workflow !== workflow) return null;
    if (reviewerOnly || actor.role !== "client" || actor.uid !== payment.recipient_id) {
      await this.assertReviewer(actor);
    } else {
      await this.currentAccount(actor);
    }
    return payment;
  }

  private paymentRef(id: string) {
    verifyId(id);
    return this.db.doc(`payments/${id}`);
  }

  private async currentAccount(actor: AuthenticatedUser, transaction?: Transaction) {
    const ref = this.db.doc(`users/${actor.uid}`);
    const snapshot = transaction ? await transaction.get(ref) : await ref.get();
    const account = accountFrom(actor.uid, snapshot.data());
    if (!accountMatchesActor(account, actor)) throw new PermissionDeniedError();
    return account;
  }

  private async assertReviewer(actor: AuthenticatedUser, transaction?: Transaction) {
    const account = await this.currentAccount(actor, transaction);
    if (!hasPermission(account.role, "verify_payments", false, account.payments_verify)) throw new PermissionDeniedError();
    return account;
  }

  private async assertClient(actor: AuthenticatedUser, tx: Transaction) {
    const snapshot = await tx.get(this.db.doc(`users/${actor.uid}`));
    const account = accountFrom(actor.uid, snapshot.data());
    if (actor.role !== "client" || !accountMatchesActor(account, actor)) throw new PermissionDeniedError();
    if (!onboardingReady(snapshot.get("onboarding"))) throw new PackageError(409, "Complete or skip onboarding before choosing a package.");
    return account;
  }

  private storage() {
    if (!this.photoStorage) throw unavailable();
    return this.photoStorage;
  }
}

function checkoutTerms(member: MembershipRecord, revision: number) {
  const token = member.checkout_token ?? member.id;
  const reference = `FN-${sha256(`${token}:${revision}`).slice(0, 24).toUpperCase()}`;
  return { reference, qr_payload: `FITNEP-TEST-NOT-PAYABLE:${reference}`, revision };
}

function parsePhoto(input: Record<string, unknown>) {
  const { proof_base64: encoded, content_type: contentType } = input;
  if (typeof encoded === "string" && encoded.length <= 4 * Math.ceil(maxPhotoBytes / 3) && isPhotoMimeType(contentType)) {
    const bytes = Buffer.from(encoded, "base64");
    if (bytes.length <= maxPhotoBytes && bytes.toString("base64") === encoded && photoContentType(bytes) === contentType) {
      return { bytes, contentType };
    }
  }
  throw new PackageError(400, "Choose a valid JPEG, PNG or WebP image up to 512 KB.");
}

function proofStorageId(digest: string) {
  if (!documentIdentifier.test(digest)) throw unavailable();
  return `payment-proof-${digest}`;
}

function unavailable() {
  return new PackageError(503, "Payment proof storage is temporarily unavailable.");
}

function verifyId(id: unknown): asserts id is string {
  if (typeof id !== "string" || !documentIdentifier.test(id)) throw new PackageError(400, "Invalid payment or membership ID.");
}

function requiredReason(value: unknown) {
  const reason = typeof value === "string" ? value.trim() : "";
  if (!reason || reason.length > 400) throw new PackageError(400, "Enter a reason up to 400 characters.");
  return reason;
}

function summary(payment: Payment) {
  const { id, membership_id, client_id, client_name, package: packageSnapshot, amount_npr,
    currency, reference, qr_payload, revision, status, created_at, reviewed_at, reviewed_by, reviewed_by_name, rejection_reason } = payment;
  return { id, membership_id, client_id, client_name, package: packageSnapshot, amount_npr, currency, reference, qr_payload,
    revision, status, created_at, reviewed_at, reviewed_by, reviewed_by_name, rejection_reason };
}
