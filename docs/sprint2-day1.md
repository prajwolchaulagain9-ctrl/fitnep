# Prajwol — Sprint 2 Day 1 handoff

Date: 22 November 2026, Asia/Kathmandu. Stories: US 73/US 6 foundation, retained
US 2/US 9 integration. Barsha remains the integration/release owner.

## Baseline and status

- Confirmed remote origin/development:
  6f0c245a96be24dcc4e3247e46f5a6e4890b41f6.
- Started sprint2/prajwol-audit-privacy from that accepted baseline.
- Implemented standalone Node hosting, persisted platform sessions, the
  append-only audit writer, denial auditing and transaction/event interfaces.
- Prepared [Render configuration](../render.yaml) and
  [deployment instructions](hosted-api.md). The user confirmed no hosted
  service exists yet and requested preparation.
- Node 22 build, unit checks and the full local emulator checks passed;
  results are recorded below.
- Hosted evidence and consumer acknowledgment remain pending. No main
  promotion, online MVP, complete story acceptance or actual-hours claim is
  made by this handoff.

## Shared interfaces for review

| Consumer | Delivered interface | Required follow-up |
| --- | --- | --- |
| Barsha | /sessions/start, /me, /activity, /end; X-FitNEP-Session; current UID/role/version/readiness/permissions | Connect Flutter and hosted credential/OTP/recovery adapters; implement failed-attempt producer against the agreed lock state |
| Tanmay | Current Auth custom-claim fields; existing privacy_acceptances/{uid} check; current role/permission invalidation | Persist acceptance/DOB/guardian state; implement account operations and increment role versions |
| Dilochan | Existing membership ID/snapshot mapping and reference-only outbox envelope | Consume activation through the assignment queue and resolve notification recipients from current server state |
| All producers | AuditEventInput, AuditWriter.appendInTransaction, appendWithEvent | Adopt inside business transactions; review names/schema before dependent work |

Acknowledgment by Barsha, Tanmay and Dilochan: **pending**. This document
prepares the handoff; it does not send a message on anyone's behalf.

### Audit storage and transaction contract

The audit_events/{serverGeneratedId} document contains verified actor
UID/name/role, action, target type/ID, outcome, server occurrence time and
non-secret correlation ID. Optional fields are operation ID, client/dietitian
IDs, business status/version and up to 50 returned record IDs.

The writer explicitly projects metadata. It rejects arbitrary extra payload
fields, forged occurrence times and invalid action/status/version values. It
does not copy tokens, session IDs, medical answers, message text or image bytes
from the actor/request. No arbitrary HTTP append/update/delete route exists;
all direct Firestore access remains denied to application accounts.

Use appendInTransaction(transaction, input) after the transaction's reads and
alongside its business writes. A rollback also rolls back the audit. Successful
workflow producers can use appendWithEvent(transaction, input, eventType); the
matching successful audit action and a non-secret operation ID are required.

The latter atomically creates:

- an immutable audit_events document;
- an immutable workflow_outbox envelope with the same event/audit ID;
- a separate outbox_deliveries document initially Pending.

Workflow audit/outbox IDs are generated deterministically by the server from
actor, operation, event type, target and version. Replaying that append cannot
duplicate or rewrite history. Producers still return their original stored
operation result before attempting an already committed append.

The delivery worker is not implemented on Day 1. Workflow/plan declarations
are internal contracts; synthetic transaction tests do not establish real
payment, assignment, intake or plan production coverage. No local mock audit
history is imported.

### Session and login-state storage

The platform_sessions/{opaqueId} document stores UID, role/version/permission
snapshot, Firebase authentication time, creation/last-human-activity/expiry
timestamps and revocation. The platform_auth_contexts/{hash(uid:auth_time)}
document prevents a captured closed/expired authentication context from
creating a new session. The opaque ID is a credential and is excluded from
audit metadata.

The platform_login_state/{uid}.locked_until field is a server-owned Timestamp
or null. The guard honors it on start and every protected request. The
failed-password attempt counter/exchange is still Barsha's Day 2 producer.
Background requests never extend idle time. Account activity, current
permission removal, required password change and saved privacy acceptance are
checked from current state.

The existing Functions/demo composition remains available for retained
emulator regressions. The standalone hosted composition requires platform
sessions and disables the demonstration activation shortcut.

### US 9 ID and snapshot mapping

| Existing boundary | Actual mapping |
| --- | --- |
| POST /memberships | Membership document ID = SHA-256 of uid + ":" + request_id |
| POST /purchases | Selection request = SHA-256 of "purchase:" + request_id; then the same membership selection service |
| /purchases/current | purchase.id is the selected membership's document ID |
| /memberships/me | membership.id identifies the same protected package_memberships record |
| Another selection for the same Pending package | Shared guard returns the existing membership ID |
| Historical customer_purchases | Retained read-only fallback; an archived ID is not a new payable Pending membership |

Barsha sends the returned canonical membership ID as membership_id. Expected
NPR price comes from the stored package.price_npr snapshot, never the client's
declared amount or a later catalog price. Pending selections have no
start/expiry dates. Managed packages retain duration_months; activation uses
calendar months, while legacy day packages retain day durations.

FirestorePackageService.activateVerifiedPayment still owns its guarded
activation transaction. For Day 3 atomic payment decision + activation +
audit/outbox, Barsha/Prajwol must adapt that shared transaction boundary rather
than chaining independent commits. Day 1 does not claim that integration is
already complete.

## Verification

Environment: Windows; Node 22.23.5; Firebase CLI 15.32.0; synthetic demo-fitnep
Auth, Functions and Firestore emulators. No live hosted test was performed.

| Check | Result | Evidence level |
| --- | --- | --- |
| npm --prefix functions run build | Passed | Compiled the final standalone/Functions source on Node 22 |
| npm --prefix functions test | 59 passed, 0 failed | Unit/API regression run; emulator suites are not enabled in this command alone |
| Full three-emulator command below | 61 passed, 0 failed, 0 skipped | Real local Firebase Auth/Firestore and Functions regression run |
| Compiled standalone entry point with invalid synthetic secret JSON | Exit 1; rejected without printing the supplied value | Startup/configuration smoke check |

The full emulator run includes all nine Day 1 scenarios: trusted identities,
logout replay, persisted session reconstruction, human idle expiry, owner
tampering, current role/permission/readiness changes, login-lock consumption,
audit/outbox rollback and replay, direct SDK denial, and US 9 ID/snapshot
mapping. The retained password-reset callable and existing workflow triggers
also passed.

Run with Node 22 and a supported Java runtime:

~~~powershell
$env:JAVA_HOME = 'D:\studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:JAVA_TOOL_OPTIONS = '-Xmx384m -XX:ActiveProcessorCount=2'
$env:FITNEP_RUN_TRIGGER_TESTS = 'true'
npm --prefix functions run build
firebase emulators:exec --config firebase.json --only auth,functions,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:emulator"
~~~

Include all three emulators: the retained recovery test calls checkSession on
port 5001. Synthetic health/build metadata and API reconstruction establish
local behavior; they do not establish provider hosting, a full process restart,
native Android/iOS behavior, or later business-producer integration.

## Remaining Day 1 exit conditions

- [ ] Review and acknowledge the account/session/owner/event/version interfaces.
- [ ] Review/merge the feature change into development.
- [ ] Create the Render service, configure private credentials and deploy.
- [ ] Record real HTTPS /healthz, deployed SHA and restart persistence.
- [ ] Coordinate iOS/signing access with Barsha; Windows tests are not iOS evidence.

Day 2 remains responsible for assigned support-team privacy and auditable
private list/detail/photo reads. Day 3 connects actual producers and durable
delivery. Day 5 supplies the readonly audit UI/filters.
