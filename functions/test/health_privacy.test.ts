import assert from "node:assert/strict";
import { it } from "node:test";
import { Transaction } from "firebase-admin/firestore";

import { AuditEventInput, AuditUnavailableError } from "../src/audit";
import { AuditedHealthReadService, healthSharingChoices } from "../src/audited_health_reads";
import { AuthenticatedUser } from "../src/domain";
import { currentAssignedTeam, PrivateRecordAccessService, PrivateRecordAuthorizationError } from "../src/nutrition_record_access_service";
import { defaultSharingChoices } from "../src/privacy_preferences_repository";

const client: AuthenticatedUser = { uid: "client-a", role: "client" };
const otherClient: AuthenticatedUser = { uid: "client-b", role: "client" };
const dietitian: AuthenticatedUser = { uid: "dietitian-1", role: "dietitian" };
const staff: AuthenticatedUser = { uid: "staff-1", role: "staff" };
const admin: AuthenticatedUser = { uid: "admin-1", role: "admin", permissions: { auditRead: true, paymentsVerify: true } };

function fixture() {
  const state = { assignment: { active: true, dietitian_id: dietitian.uid, team_member_ids: [staff.uid, admin.uid] } as Record<string, unknown>,
    accepted: true, shared: true };
  const access = new PrivateRecordAccessService({
    async getCurrentTeam() { return currentAssignedTeam(state.assignment); },
  }, {
    async getForClient() {
      return { ...defaultSharingChoices, shareNutritionRecords: state.shared, shareMealPhotos: state.shared,
        shareProgressPhotos: state.shared, shareActivityData: state.shared, updatedAt: null };
    },
  }, { async hasCurrentAcceptance() { return state.accepted; } });
  return { state, access };
}

it("uses one owner/current-team policy for current reads and future plan, weight, message and intake adapters", async () => {
  const { access } = fixture();
  for (const choice of Object.values(healthSharingChoices)) {
    for (const actor of [client, dietitian, staff, admin]) await access.assertCanRead(actor, client.uid, choice);
    for (const actor of [otherClient, { ...dietitian, uid: "dietitian-2" }, { ...staff, uid: "staff-2" }, { ...admin, uid: "admin-2" }]) {
      await assert.rejects(access.assertCanRead(actor, client.uid, choice), PrivateRecordAuthorizationError);
    }
  }
});

it("rechecks assignment and sharing on every request and leaves owner-only drafts private", async () => {
  const { state, access } = fixture();
  for (const assignment of [undefined, { active: false, dietitian_id: dietitian.uid },
    { active: true, dietitian_id: dietitian.uid, team_member_ids: null },
    { active: true, dietitian_id: "dietitian-2", team_member_ids: ["staff-2"] }]) {
    state.assignment = assignment as Record<string, unknown>;
    for (const actor of [dietitian, staff, admin]) {
      await assert.rejects(access.assertCanRead(actor, client.uid, "shareNutritionRecords"), PrivateRecordAuthorizationError);
    }
    await access.assertCanRead(client, client.uid, "shareNutritionRecords");
  }
  state.assignment = { active: true, dietitian_id: dietitian.uid, team_member_ids: [staff.uid, admin.uid] };
  state.shared = false;
  await assert.rejects(access.assertCanRead(staff, client.uid, "shareNutritionRecords"), PrivateRecordAuthorizationError);
  await access.assertCanRead(client, client.uid, "shareNutritionRecords");
  state.shared = true;
  for (const actor of [dietitian, staff, admin]) {
    await assert.rejects(access.assertCanRead(actor, client.uid, "shareNutritionRecords", true), PrivateRecordAuthorizationError);
  }
  await access.assertCanRead(client, client.uid, "shareNutritionRecords", true);
});

it("requires the current team policy for internal reads and collection", async () => {
  const { state, access } = fixture();
  state.accepted = false;
  for (const actor of [dietitian, staff, admin]) {
    await assert.rejects(access.assertCanRead(actor, client.uid, "shareMealPhotos"), PrivateRecordAuthorizationError);
  }
  await assert.rejects(access.assertCanCollect(client, client.uid, "shareNutritionRecords"), PrivateRecordAuthorizationError);
  await access.assertCanRead(client, client.uid, "shareMealPhotos");
});

it("audits the exact returned IDs and resource version while excluding clinical values", async () => {
  const { access } = fixture();
  const events: AuditEventInput[] = [];
  const transaction = {} as Transaction;
  const reader = new AuditedHealthReadService(access, {
    appendInTransaction(actual, event) { assert.equal(actual, transaction); events.push(event); return "audit-id"; },
  });
  const answers = [{ id: "submitted-2", allergy: "private answer" }];
  const result = await reader.read(transaction, staff, { clientId: client.uid, category: "intakes", version: 2 }, "server-correlation",
    async () => ({ data: answers, recordIds: ["submitted-2"] }));
  assert.equal(result, answers);
  assert.equal(events[0]?.action, "health.read");
  assert.equal(events[0]?.targetId, "client-a/intakes");
  assert.deepEqual(events[0]?.recordIds, ["submitted-2"]);
  assert.equal(events[0]?.version, 2);
  assert.equal(events[0]?.dietitianId, dietitian.uid);
  assert.equal(JSON.stringify(events).includes("private answer"), false);
});

it("returns no health result when authorization or audit persistence fails", async () => {
  const { access } = fixture();
  let loaded = false;
  const reader = new AuditedHealthReadService(access, {
    appendInTransaction() { throw new AuditUnavailableError(); },
  });
  const load = async () => { loaded = true; return { data: "private data" }; };
  const target = { clientId: client.uid, category: "weight-history" as const, recordId: "weight-1" };
  await assert.rejects(reader.read({} as Transaction, otherClient, target, "request-1", load), PrivateRecordAuthorizationError);
  assert.equal(loaded, false);
  await assert.rejects(reader.read({} as Transaction, staff, target, "request-2", load), AuditUnavailableError);
  assert.equal(loaded, true);
});
