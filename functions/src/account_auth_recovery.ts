import { Auth } from "firebase-admin/auth";
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { accountFrom } from "./account_service";
import { FirestoreAuditWriter } from "./audit";

/** Canonical Firestore changes deny old authority immediately; Auth sync is retriable. */
export async function reconcileAccountAuth(auth: Auth, db: Firestore): Promise<number> {
  const pending = await db.collection("account_auth_operations").where("state", "==", "requested").limit(25).get();
  let completed = 0;
  for (const document of pending.docs) {
    const operation = document.data();
    try {
      const current = accountFrom(operation.target_id, (await db.doc(`users/${operation.target_id}`).get()).data());
      // A superseded operation must not restore a former role or active state.
      if (current.role_revision !== operation.revision) {
        await document.ref.update({ state: "superseded", finished_at: FieldValue.serverTimestamp() });
        continue;
      }
      const identity = await auth.getUser(current.id);
      await auth.setCustomUserClaims(current.id, { ...identity.customClaims, role: current.role });
      await auth.updateUser(current.id, { disabled: current.account_status !== "active" });
      await auth.revokeRefreshTokens(current.id);
      await db.runTransaction(async tx => {
        const [receipt, account] = await Promise.all([tx.get(document.ref), tx.get(db.doc(`users/${current.id}`))]);
        if (receipt.get("state") !== "requested") return;
        if (account.get("role_revision") !== operation.revision) {
          tx.update(document.ref, { state: "superseded", finished_at: FieldValue.serverTimestamp() }); return;
        }
        new FirestoreAuditWriter(db).appendInTransaction(tx, {
          actor: operation.actor, action: "account.auth_synchronized", targetType: "account", targetId: current.id,
          version: operation.revision, status: current.account_status, outcome: "succeeded",
          operationId: document.id, correlationId: operation.correlation_id,
        });
        tx.update(document.ref, { state: "completed", finished_at: FieldValue.serverTimestamp() });
      });
      completed++;
    } catch {
      await document.ref.update({ state: "requested", last_error: "auth-sync-unavailable", last_attempt_at: Timestamp.now(),
        attempt_count: FieldValue.increment(1) });
    }
  }
  return completed;
}
