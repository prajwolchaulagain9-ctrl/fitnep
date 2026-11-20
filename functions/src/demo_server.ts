import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { FirebaseAuthVerifier } from "./auth";
import { FirestoreNotificationRepository } from "./firestore_notification_repository";
import { FirestorePrivacyPreferencesRepository } from "./firestore_privacy_preferences_repository";
import { createNotificationApp } from "./http_app";
import { FirestorePackageService } from "./package_membership_service";

// This runner is deliberately emulator-only: it cannot seed a live project.
for (const name of ["FIREBASE_AUTH_EMULATOR_HOST", "FIRESTORE_EMULATOR_HOST"]) {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env[name] ?? "")) {
    throw new Error(`${name} must point to a local emulator.`);
  }
}
const firebase = initializeApp({ projectId: "demo-fitnep" });
const auth = getAuth(firebase);
const db = getFirestore(firebase);

async function main() {
  for (const [uid, role] of [["demo-client", "client"], ["demo-admin", "admin"]] as const) {
    try { await auth.getUser(uid); } catch (error) {
      if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
      await auth.createUser({ uid, email: `${uid}@fitnep.test`, password: "FitnepDemo123!", displayName: role === "client" ? "Demo Client" : "Demo Admin" });
    }
    await auth.setCustomUserClaims(uid, { role });
  }
  for (const [id, name, days, price, features] of [
    ["basic", "Basic", 30, 2500, ["Personalized nutrition plan", "Weekly check-ins"]],
    ["standard", "Standard", 60, 4500, ["Nutrition and workout plans", "Weekly progress reviews", "Care team support"]],
    ["premium", "Premium", 90, 8000, ["Personalized coaching", "Nutrition and workout plans", "Progress reviews", "Priority care team support"]],
  ] as const) {
    await db.collection("package_catalog").doc(id).set({ name, duration_days: days, price_npr: price, features: [...features], active: true });
  }
  const api = createNotificationApp({
    authVerifier: new FirebaseAuthVerifier(),
    notificationRepository: new FirestoreNotificationRepository(db),
    privacyPreferencesRepository: new FirestorePrivacyPreferencesRepository(db),
    packageService: new FirestorePackageService(db),
  });
  const server = api.listen(3000, "127.0.0.1", () => {
    console.log("Free FitNEP demo ready at http://127.0.0.1:3000. No real money is processed.");
  });
  const close = () => server.close(() => { void deleteApp(firebase).finally(() => process.exit(0)); });
  process.once("SIGINT", close);
  process.once("SIGTERM", close);
}
void main().catch(error => { console.error("Could not start the local demo", error); process.exitCode = 1; });
