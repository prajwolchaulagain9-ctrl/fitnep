import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { FirestoreAccountService, FirestoreAuditStore } from "./account_service";
import { FirebaseAuthVerifier } from "./auth";
import { createNotificationApp } from "./http_app";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { FirestorePrivateRecordsStore } from "./firestore_private_records_store";
import { FirestorePackageService } from "./package_membership_service";
import { FirestorePackageRepository } from "./firestore_package_repository";
import { FirestorePurchaseRepository } from "./firestore_purchase_repository";

// Reusable Express handler for the existing Firebase function or a Node serverless
// host. Credentials come from that host's trusted environment, never Flutter.
export function createFitnepApi() {
  if (getApps().length === 0) initializeApp();
  const db = getFirestore(), accounts = new FirestoreAccountService(db, getAuth());
  const preferences = new FirestorePrivacyPreferencesRepository(db);
  return createNotificationApp({ accounts, audit: new FirestoreAuditStore(db),
    authVerifier: new FirebaseAuthVerifier(accounts), notificationRepository: new FirestoreNotificationRepository(db),
    privacyPreferencesRepository: preferences, privateRecordsStore: new FirestorePrivateRecordsStore(db, preferences),
    packageService: new FirestorePackageService(db), packageRepository: new FirestorePackageRepository(db),
    purchaseRepository: new FirestorePurchaseRepository(db),
  });
}
