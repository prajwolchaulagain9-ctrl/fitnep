import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { setTimeout } from "node:timers/promises";
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { FirestorePackageService } from "../src/package_service";

const enabled = process.env.FITNEP_RUN_TRIGGER_TESTS === "true" && process.env.FIRESTORE_EMULATOR_HOST;
(enabled ? describe : describe.skip)("Package verified-payment Firestore trigger", () => {
  const app = initializeApp({ projectId: "demo-fitnep" }, "package-trigger-check");
  const db = getFirestore(app);
  const service = new FirestorePackageService(db);
  before(async () => {
    await db.collection("package_catalog").doc("trigger-package").set({ active: true, name: "Trigger fixture", price_npr: 1000, duration_days: 30, features: ["Nutrition support"] });
  });
  after(async () => { await deleteApp(app); });
  it("waits for verification, activates the selected membership, and safely replays", async () => {
    const selected = await service.select("trigger-package-client", "trigger-package", "trigger-selection-0001");
    const payment = db.collection("payments").doc("package-trigger-payment");
    await payment.set({ membership_id: selected.id, recipient_id: "trigger-package-client", amount_npr: 1000, currency: "NPR", status: "paid", verified: false });
    await setTimeout(1500);
    assert.equal((await db.collection("package_memberships").doc(selected.id).get()).get("status"), "pending");
    await payment.update({ verified: true });
    const activated = await waitFor(async () => {
      const snapshot = await db.collection("package_memberships").doc(selected.id).get();
      return snapshot.get("status") === "active" ? snapshot.data() : undefined;
    });
    assert.equal(activated.payment_id, payment.id);
    assert.equal(Date.parse(activated.end_at) - Date.parse(activated.start_at), 30 * 86_400_000);
    await payment.update({ audit_note: "Replay verification" });
    await setTimeout(1500);
    const replayed = (await db.collection("package_memberships").doc(selected.id).get()).data()!;
    assert.deepEqual(replayed, activated);
  });
});

async function waitFor<T>(read: () => Promise<T | undefined>): Promise<T> {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const value = await read();
    if (value !== undefined) return value;
    await setTimeout(250);
  }
  throw new Error("Package payment trigger did not activate its membership.");
}
