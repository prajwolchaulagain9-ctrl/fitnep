import { getApps, initializeApp } from "firebase-admin/app";
import { Auth, getAuth } from "firebase-admin/auth";
import { Firestore, getFirestore } from "firebase-admin/firestore";
import { FirestoreAuditWriter } from "./audit";
import { FirestoreAccountService, FirestoreAuditStore } from "./account_service";
import { FirebaseAuthVerifier } from "./auth";
import { FirebaseStaffAccountRepository } from "./firebase_staff_account_repository";
import { createNotificationApp } from "./http_app";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { FirestorePrivateRecordsStore } from "./firestore_private_records_store";
import { FirestorePackageService } from "./package_membership_service";
import { FirestorePackageRepository } from "./firestore_package_repository";
import { FirestorePurchaseRepository } from "./firestore_purchase_repository";
import { BrevoMailer } from "./brevo_mailer";
import { GooglePasswordService } from "./google_password_service";
import { ClientAssignmentService, ExistingClientPackageStatusReader, ExistingStaffDietitianDirectory,
  FirebaseClientDirectory } from "./client_assignment_service";
import { FirestoreClientAssignmentRepository } from "./firestore_client_assignment_repository";
import { NotificationWorkflowService } from "./notification_service";
import { ClientIntakeService } from "./client_intake_service";
import { FirestoreClientIntakeRepository } from "./firestore_client_intake_repository";
import { cloudinaryPhotoStorageFromEnv, PhotoMimeType, PrivatePhotoStorage } from "./cloudinary_photo_storage";
import { CheckoutPayments } from "./checkout_payments";
import { PrivateRecordsError } from "./private_records";

// Reusable Express handler for the existing Firebase function or a Node serverless
// host. Credentials come from that host's trusted environment, never Flutter.
export function createFitnepApi() {
  if (getApps().length === 0) initializeApp();
  return createNotificationApp(createFitnepDependencies(getAuth(), getFirestore()));
}

export function createFitnepDependencies(auth: Auth, db: Firestore, photoStorage?: PrivatePhotoStorage) {
  const emulator = /^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? "");
  const privatePhotoStorage = photoStorage ?? (emulator ? undefined : cloudinaryPhotoStorageFromEnv());
  const proofStorage = privatePhotoStorage ?? (emulator ? emulatorProofStorage(db) : undefined);
  const accounts = new FirestoreAccountService(db, auth);
  const preferences = new FirestorePrivacyPreferencesRepository(db);
  const auditWriter = new FirestoreAuditWriter(db);
  const notificationRepository = new FirestoreNotificationRepository(db);
  const staffAccountRepository = new FirebaseStaffAccountRepository(auth, db);
  const packageService = new FirestorePackageService(db);
  return { accounts, audit: new FirestoreAuditStore(db),
    auditWriter,
    authVerifier: new FirebaseAuthVerifier(accounts), notificationRepository, staffAccountRepository,
    privacyPreferencesRepository: preferences, privateRecordsStore: new FirestorePrivateRecordsStore(db, preferences, auditWriter, privatePhotoStorage),
    packageService, packageRepository: new FirestorePackageRepository(db),
    checkoutPayments: new CheckoutPayments(db, packageService, auditWriter, proofStorage),
    purchaseRepository: new FirestorePurchaseRepository(db),
    googlePasswordService: new GooglePasswordService(auth, db, new BrevoMailer(process.env), process.env.SIGNUP_OTP_HASH_SECRET || ""),
    clientAssignmentService: new ClientAssignmentService(new FirestoreClientAssignmentRepository(db, auditWriter),
      new ExistingClientPackageStatusReader(packageService), new ExistingStaffDietitianDirectory(staffAccountRepository),
      new NotificationWorkflowService(notificationRepository), new FirebaseClientDirectory(auth), undefined, true),
    clientIntakeService: new ClientIntakeService(
      new FirestoreClientIntakeRepository(db, auditWriter),
    ),
  };
}

function emulatorProofStorage(db: Firestore): PrivatePhotoStorage {
  const photos = db.collection("emulator_payment_proofs");
  return {
    async write(id: string, bytes: Buffer, contentType: PhotoMimeType) {
      await photos.doc(id).create({ bytes, content_type: contentType });
    },
    async read(id: string, contentType: PhotoMimeType) {
      const photo = await photos.doc(id).get();
      if (photo.get("content_type") !== contentType || !Buffer.isBuffer(photo.get("bytes"))) {
        throw new PrivateRecordsError(404, "Photo not found.");
      }
      return photo.get("bytes") as Buffer;
    },
  };
}
