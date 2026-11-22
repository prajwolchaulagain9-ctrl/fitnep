# Barsha Day 1 consumer integration

This is a local integration checkpoint on `barsha`. No GitHub push, Render
deployment, Firebase deployment, billing change, duplicate service, or live OTP
delivery was performed for this integration.

## Preservation and development integration

The pre-merge checkpoint is
`c1d3a7d03d5fe2e6ef7fe39f103f99f4946b7b0c`. It contains all 43 modified tracked
and 23 new files that were present before integration. Ignored local credentials
and generated output are excluded from Git.

The SHA-256 manifest in `.dart_tool/day1-preservation-20261122/manifest.json`
verifies 78 preservation copies, including the changed files and clean
authentication/configuration dependencies. Incoming merge inputs are separately
preserved in `.dart_tool/day1-merge-inputs-20261122/`.

The integrated development tip is
`b7e6f2981bda6793d8ee0c7ff742c8b5f3958edc`. Conflict reconciliation retains the
canonical RBAC services, dashboards, route guards, record ownership checks and
existing Login, Signup and Verify Email screen source. Welcome, application
theme and the emulator-only demo entry are also retained. Incoming staff
management, membership changes, hosting configuration and session/audit
interfaces are integrated around those components.

Recovery does not require discarding the merged work: inspect an original file
with `git show c1d3a7d:<path>`, copy its verified preservation version into a
separate recovery directory, or extract `git archive c1d3a7d` into a separate
directory. Review the recovered content before selectively restoring anything.
Do not reset or clean the current working tree.

## Account, credential and session agreement

- Firebase native SDKs continue email/password and Google credential exchange.
  Firebase remains the issuer of ID and refresh tokens.
- The Express verifier checks Firebase token revocation, current identity,
  credential-generation markers and the canonical `users/{uid}` role/status.
  Current database roles, rather than captured token claims, determine access.
- `users.role_revision` appears as `role_version` in the hosted session contract.
  Both account-management adapters update canonical roles/status. Trusted Auth
  claims provision an absent canonical profile once; they never overwrite one.
- `/session` returns only the verified user's account/permission metadata and
  current password-setup requirement. It is available before platform session
  creation so OTP, privacy and temporary-password prerequisites can complete.
- Business operations require both `Authorization: Bearer ...` and
  `X-FitNEP-Session`. The hosted composition disables demonstration payment
  verification. The emulator/Functions regression composition remains available.
- Every platform request checks current role/revision, UID, authentication time,
  credential readiness, login lock, expiry and (for clients) privacy acceptance.

## Flutter session lifecycle

`HostedSessionService` consumes `/sessions/start`, `/sessions/me`,
`/sessions/activity` and `/sessions/end`. Opaque session credentials are held in
secure storage, bound to UID and Firebase authentication time. Stored roles and
permissions are never used as authority. Concurrent restoration requests share
one handshake; account changes cannot save an older response.

An existing session restores through `/me`. An explicitly reported authority
change may rotate an open context through `/start`, preserving its original
expiry and human activity time. Closed, revoked or expired contexts require a
new sign-in. API requests, polling, lifecycle resume and restarts do not renew
idle expiry. Only taps/keyboard input report throttled human activity.

Public health checks and idempotent session operations have a bounded cold-start
retry. Loading/error states guard protected content. On logout the local session
is removed and an encrypted, short-lived pending-logout credential is reconciled
at the next startup/request if the host was unreachable. Identity/role changes
clear existing protected page data and close restricted dialogs.

## Hosted prerequisite adapters

| Endpoint | Authority and behavior |
| --- | --- |
| `/auth/signup/otp/send` | Verified Firebase identity supplies UID/email; existing transactional Brevo OTP service supplies limits and delivery |
| `/auth/signup/otp/verify` | Checks owner-bound code/expiry/attempt limits, then updates Firebase email verification |
| `/auth/privacy` | Current canonical role and verified owner; server timestamps and validated minor consent |
| `/auth/staff/change-temporary-password` | Current account, credential marker and recent password sign-in; revokes credentials after change |
| `/auth/recovery/request` | Firebase reset delivery with account enumeration protection |
| `/auth/recovery/verify` | Firebase-issued expiring action code |
| `/auth/recovery/confirm` | Firebase password policy and single-use reset; clears the local session |

Clients cannot send another UID/email/role to OTP operations or write consent,
roles, audit records or platform sessions directly through Firestore.

Denied requests use `permission-denied` and server-owned `audit_logs`. The
incoming append-only `audit_events` contract records session lifecycle and
protected request denials. Tokens, opaque session IDs, passwords, OTPs and
private record contents are excluded from audit metadata. Record access still
requires the owner or the current permitted assignment and sharing consent.

## Verification and evidence limits

- Flutter analysis: no issues found.
- Flutter regressions: 152 passed; Login/Signup/OTP, recovery, four dashboards/menus, live
  role-change cleanup, UID-bound restoration, offline logout and human activity.
- Node 22 backend unit/API checks: 73 passed, including hosted recovery adapters.
- Node 22 Auth/Firestore/Functions emulator checks: 91 passed, zero skipped.
- A separate local Node process was stopped and replaced; the same persisted
  session restored with unchanged expiry and no duplicate session-start event.
- Actual existing Render-service restart: **pending**. Local process evidence
  establishes persistence behavior, not live-provider/native-device acceptance.

Raw emulator logs stay ignored locally; they may contain synthetic test reset
links. No live account was created and no real OTP was sent during these tests.

## Release tasks requiring approval

1. Review this local merge; approve pushing `barsha` when ready. Render's existing
   blueprint tracks `development` with automatic deploys disabled. Coordinate a
   reviewed promotion to that branch and a manual deployment of the existing
   service; do not create another service or database.
2. Verify host-secret configuration without disclosing values:
   `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_JSON` or ADC,
   `BREVO_API_KEY`, `SIGNUP_OTP_HASH_SECRET`, `BREVO_SENDER_EMAIL`, and
   `FIREBASE_WEB_API_KEY`. Render already supplies port/build metadata. Keep
   the existing OTP hash secret across restarts so outstanding codes survive.
3. Validate existing `users` documents against role/status/timestamp/revision
   requirements. Absent profiles provision from trusted existing identities;
   malformed existing profiles must be repaired by an operator. No roles are
   silently reassigned. Retain current client assignment revisions.
4. Deploy the reconciled Firestore rules/indexes to `fitnep-88908`. The rules
   retain backend-only records and add the self-only `account_access` signal.
   Firestore and external Node hosting can remain on Spark; do not deploy
   Firebase Functions or upgrade billing for this architecture.
5. Build with `API_BASE_URL=https://fitnep-api.onrender.com/` using the reviewed
   example configuration. The live baseline predates `/session` metadata and
   these hosted OTP/recovery adapters; enabling the client before deploying its
   compatible backend will fail closed.
6. With an existing authorized test account, save an open platform session,
   restart the existing Render service, then verify `/healthz`, deployed SHA,
   `/sessions/me`, unchanged UID/expiry, record denial and logout replay. Keep
   credentials out of shared evidence. Verify the same lifecycle on Android.

Remaining beyond Day 1: failed-password lockout production (Day 2), durable
business-event delivery/producers (Day 3), and native iOS/signing acceptance.
The standalone server does not execute Firebase Functions triggers; these later
producer/worker integrations require their own tests before claiming delivery.
