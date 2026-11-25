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

// Reusable Express handler for the existing Firebase function or a Node serverless
// host. Credentials come from that host's trusted environment, never Flutter.
export function createFitnepApi() {
  if (getApps().length === 0) initializeApp();
  return createNotificationApp(createFitnepDependencies(getAuth(), getFirestore()));
}

export function createFitnepDependencies(auth: Auth, db: Firestore) {
  const accounts = new FirestoreAccountService(db, auth);
  const preferences = new FirestorePrivacyPreferencesRepository(db);
  const auditWriter = new FirestoreAuditWriter(db);
  const notificationRepository = new FirestoreNotificationRepository(db);
  const staffAccountRepository = new FirebaseStaffAccountRepository(auth, db);
  const packageService = new FirestorePackageService(db);
  return { accounts, audit: new FirestoreAuditStore(db),
    auditWriter,
    authVerifier: new FirebaseAuthVerifier(accounts), notificationRepository, staffAccountRepository,
    privacyPreferencesRepository: preferences, privateRecordsStore: new FirestorePrivateRecordsStore(db, preferences, auditWriter),
    packageService, packageRepository: new FirestorePackageRepository(db),
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
