# FitNep API and Firebase notification backend

This folder contains the mobile application's Firebase Cloud Functions backend.
It exposes authenticated HTTPS APIs for the Flutter app; it does not contain a
website or browser UI.

The shared project stays on **Spark**. These Functions are local emulator
implementations; they are not deployed. Cloud Functions deployment requires a
billing-enabled project and is outside the agreed scope. The Flutter API URL
defaults to empty until a supported backend is supplied.

Sprint 2 adds a standalone Node 22 runner in src/server.ts. After building,
npm start runs the same Express API against cloud Firebase Auth/Firestore
with opaque platform sessions and backend-created audit storage. The
[Render setup](../docs/hosted-api.md) and [Day 1 handoff](../docs/sprint2-day1.md)
describe configuration and remaining integrations. The Node API is live at
https://fitnep-api.onrender.com. Eight hosted health/session/audit checks passed
on 22 November 2026; see the [verification evidence](../docs/sprint2-day1-live-verification.json).

## Firebase project and runtime

- Project: `fitnep-88908`
- Region: `asia-south1`
- Runtime: Node.js 22
- Exported HTTPS function: `api`
- Recovery callable: `checkSession`, in `us-central1`
- Optional signup callables: `sendSignupEmailCode` and `verifySignupEmailCode`,
  in `us-central1`; see [signup configuration](../docs/signup.md).
- Shared entry point: `lib/index.js`, built from TypeScript; it also exports
  the existing CommonJS recovery callable from `src/index.cjs`.

For local emulators, configure an Android emulator with:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5001/demo-fitnep/asia-south1/api/
```

## Authentication and roles

Every API request must include a Firebase ID token:

```text
Authorization: Bearer <firebase-id-token>
```

Assigned roles use one of these trusted custom claims:

```json
{ "role": "admin" }
{ "role": "dietitian" }
{ "role": "client" }
```

Role claims must be assigned by a trusted administrative process using the
Firebase Admin SDK. Never allow the mobile app to assign or edit its own role.
An account with a signed `email_verified: true` claim and no assigned `role`
receives standard client access. Unsupported assigned roles and unverified
accounts without a role are rejected. Firebase token verification always checks
revocation before resolving the role.

All roles are scoped to their own `uid` for notification access. Admin and
Dietitian roles do not receive an implicit bypass to client notifications.

## Privacy preferences API

- `GET /privacy/preferences`
- `PATCH /privacy/preferences` with `{ "share_nutrition_records": true }`

Only the authenticated Client can read or update their own preference; the
server derives the client ID from the verified token. Preferences are stored in
`privacy_preferences/{clientUid}` and default to sharing disabled. Nutrition
record read handlers must call `NutritionRecordAccessService.assertCanRead`
before returning records. The gate permits the client to read their own records;
a dietitian must be the current assignee and sharing must be enabled. Assignment
storage is server-owned in `client_assignments/{clientId}`; direct mobile
Firestore access remains denied.

## Notification APIs

- `GET /notifications`
- `GET /notifications/:notificationId`
- `PATCH /notifications/:notificationId/read`
- `PATCH /notifications/read-all`

Recipient identity is always derived from the verified token. Requests that
try to supply `recipient_id`, `recipientId`, `user_id`, or `userId` are rejected.
Unknown and unauthorized notification IDs both return `404` to avoid leaking
whether another user's notification exists.

## Package APIs

- `GET /packages` lists packages for any authenticated FitNep role.
- `GET /admin/packages` lists active and inactive packages for administrators.
- `GET /admin/package-history` lists durable package changes for administrators.
- `POST /packages` creates a package for an `admin` role only.
- `PATCH /packages/:packageId` edits the current offer for future purchases.
- `PATCH /packages/:packageId/active` activates or deactivates an offer.

The create body uses `request_id`, `name`, `duration_months`, `price`, and
`feature_description`. The request identifier makes retries idempotent. Package
name and feature description are required, duration must be a positive whole
number of months, and price must be positive. Records are stored in the
Firestore `packages` collection. Direct mobile reads and writes remain denied
by Firestore rules.

Create, edit, activate, and deactivate operations also write a record to
Firestore `package_change_history` in the same transaction as the package
mutation. Each record contains the package reference and name, verified admin
UID and token-derived display name/email, action, changed timestamp, and the
previous/new values that changed. Repeated idempotent creates and no-op edits or
status requests do not create duplicate history. Direct mobile history reads
and writes are denied; administrators read history through the API.

## Client assignment APIs

- `GET /admin/client-assignments/:clientId/eligibility` returns the client's
  effective package status and whether assignment is allowed.
- `GET /admin/client-assignments/dietitian-counts` returns each dietitian's
  current number of active client assignments.
- `PUT /admin/client-assignments/:clientId` accepts `{ "dietitian_id": "..." }`.
  Reassignments atomically update the current `client_assignments/{clientId}`
  document and append immutable versioned records to
  `client_assignment_history`. Authorization reads only the current assignment,
  so the previous dietitian loses access as soon as the transaction commits.
  The same transaction appends one immutable `audit_events` record with action
  `client.assigned` or `client.reassigned`, the client, previous and new
  dietitians, trusted admin identity, assignment version, and server timestamp.

Both endpoints require an administrator. The write re-checks the existing
membership status and rejects pending, scheduled, expired, inactive, or missing
packages; only a client with an active package can be assigned to an active
dietitian.

`GET /dietitian/assigned-clients/:clientId/intake` returns the saved
`client_intakes/{clientId}` form only to the currently assigned dietitian. The
assignment and intake are read in one Firestore transaction. Allergies and
medical conditions are returned separately for priority display, while health
information, goals, restrictions, responses, and remaining intake fields are
returned as complete sections. Direct mobile access to intake documents is
denied.

## Customer purchase APIs

- `POST /purchases` creates a Pending package selection for the authenticated
  customer.
- `GET /purchases/current` returns that customer's latest selection or verified
  membership terms.

The purchase body contains `package_id` and an idempotent `request_id`. The
backend reads the current package and stores its immutable terms in a protected
`package_memberships` record. Pending responses have no start or expiry dates;
admin verification assigns them through the shared overlap guard. Membership
reads use the saved terms rather than the mutable catalog document. Existing
historical snapshots at `customer_purchases/{customerId}/purchases/{requestId}`
remain readable through the API.

These APIs process no money and include no payment gateway. Only trusted admin
verification activates a membership; clients cannot override its owner, price
or activation status.

## Workflow hooks

Cloud Functions listen to backend-owned Firestore workflow collections for:

- `diet_plans/{planId}` creation;
- `messages/{messageId}` creation;
- `tasks/{taskId}` creation;
- `payments/{paymentId}` transitions into `paid`, `confirmed`, or `succeeded`.

Each hook derives a stable event key so retries do not create duplicates.
Pending and failed payments are ignored. These hooks are backend-only and are
not exposed as public HTTP routes. Workflow documents accept the existing
camel-case names as aliases, but the preferred fields are:

| Workflow | Required notification fields |
|---|---|
| Diet plan | `client_id`, `assigned_by_id`, `assigned_by_role`; optional `title` |
| Message | `conversation_id`, `recipient_id`; optional `sender_name` |
| Task | `assignee_id`, `assigned_by_id`, `assigned_by_role`; optional `title` |
| Payment | `recipient_id`, `status`; optional `amount_label` |

Only trusted backend code may write these collections. The included Firestore
rules reject direct mobile reads and writes.

## Firestore storage

Production uses `FirestoreNotificationRepository`. Notification documents are
stored in `notifications` with this schema:

- `id` (Firestore document ID)
- `recipient_id`
- `title`
- `message`
- `type`
- `reference_id`
- `is_read`
- `created_at`
- `event_key` (internal idempotency key)

Every query and mutation includes the authenticated user's UID. Deterministic
SHA-256 document IDs and Firestore transactions make workflow retries
idempotent. Composite indexes are declared in `../firestore.indexes.json`.

## Commands

```powershell
cd functions
npm ci
npm run build
npm test
```

The declared Node 22 runtime uses Firebase Admin 14 and pins its database-compat
dependency to the previously tested Node-compatible release. Keep the lockfile
when installing shared dependencies.

Run the combined recovery, notification and workflow security tests from the
repository root. These tests use only `demo-fitnep`, never the live project:

```powershell
$env:JAVA_HOME = 'D:\studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:FITNEP_RUN_TRIGGER_TESTS = 'true'
npm --prefix functions run build
firebase emulators:exec --only auth,functions,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:emulator"
```

Run all four workflow-trigger integration tests with the Functions emulator:

```powershell
$env:FITNEP_RUN_TRIGGER_TESTS = 'true'
npm --prefix functions run build
npm --prefix functions run build:test
npx --yes firebase-tools@latest emulators:exec --config firebase.json --project demo-fitnep --only firestore,functions "node --test --experimental-test-isolation=none --test-concurrency=1 functions/.test-build/test/workflow_trigger_emulator.test.js"
```

Firestore uses port 18080 in the shared configuration. The emulator-only
commands work without deploying to the Spark project.

## Seeded demo admin

From the repository root, use the existing Firebase CLI login to seed an admin
in the same Firebase project as the Android app:

```powershell
npm --prefix functions run seed:admin
```

The account uses `demo-admin@fitnep.test`, has a verified email and the trusted
`admin` role, and opens client management after login. Its generated password
is saved in the ignored `.dart_tool/demo-admin.credentials.json` file. Rerunning
the seed preserves the password and verifies that login returns an admin token.
The seed only modifies its own saved demo account.

The retained deployment script is outside the supported Spark workflow. No
Functions deployment or billing upgrade is part of this integration. A live
notification service needs a separately agreed hosting arrangement.

## US 9 packages

The shared API also implements authenticated `GET /packages`,
`GET /memberships/me` and `POST /memberships`. Selection stores a Pending
catalog snapshot. `onPackagePaymentVerified` activates only matching trusted,
verified payment records and enforces date overlap in a Firestore transaction.
See [package schema and integration](../docs/packages.md) for contracts, ownership,
date boundaries, emulator checks and the outstanding live hosting/login handoff.

The zero-budget project uses manual admin verification via
`POST /admin/memberships/{id}/verify-payment`, with audited atomic activation.
`npm run demo:serve` hosts the existing API locally against Auth/Firestore emulators.
See [free demo](../docs/free-demo.md). No gateway or paid Functions deployment is used.

## US8 privacy and consent

- After Firebase verifies their email, clients complete the privacy step before
  continuing. The default app writes its own `privacy_acceptances/{uid}` record.
  Firestore rules validate the entered age, server timestamp and guardian
  confirmation for minors. The optional `registrationPrivacy` callable writes
  the same age and consent fields. Returning clients with current acceptance
  continue directly. Keep the Flutter, Firestore rules and backend policy
  versions in sync.
  The consent rules and optional callable require a verified email.
- `GET /privacy/preferences` returns the client's current choices.
  `PATCH /privacy/preferences` accepts individual boolean fields
  `share_nutrition_records`, `share_meal_photos`, `share_progress_photos`,
  and `share_activity_data`. Missing values in older accounts default to false.
  The Flutter screen also reads and updates this same document directly.
  Firestore rules limit the screen to a verified user who has accepted the
  current policy and owns the document. Newly registered clients can manage
  their choices while they wait for their client role to be assigned.
- The private record API is `/clients/:clientId/records/:category`. The
  categories are `nutrition-records`, `meal-photos`, `progress-photos`, and
  `activity-data`. GET lists up to 50 records and accepts the returned
  `next_cursor` as `after`. POST accepts a nutrition JSON record
  (`food_name`, `calories`), an activity JSON record (`steps`,
  `active_minutes`), or raw JPEG, PNG, or WebP photo bytes up to 512 KiB.
  GET `/:recordId/photo` serves photo bytes under the same access check.
- Optional collection must go through this API. Read authorization uses the
  current trusted `client_assignments/{clientId}` document with
  `active: true` and `dietitian_id`. Clients keep owner access after
  withdrawal. The admin assignment screen writes this contract through the
  protected API; future tracker screens can read it through server checks.

## US7 staff accounts

`GET /admin/staff-accounts` requires a verified Firebase token with the admin
role. It reads team accounts from Firebase Auth and returns only their UID,
name, email, role and active status. The result includes inactive staff,
dietitians and admins. Client accounts and accounts with no recognized role are
excluded.

Pass the returned `next_cursor` as the next request's `cursor`. A page can be
empty if Firebase returned only client accounts, so continue until
`next_cursor` is null.

Admins can create a staff, dietitian or admin account with
`POST /admin/staff-accounts`. Supply `request_id`, `name`, `email`, `role`,
and `temporary_password`. The account becomes active once its setup and audit
entry are saved. Reuse the same request ID and fields when retrying.

At first sign-in, the app opens the password change screen. The pending
session can use `POST /auth/staff/change-temporary-password` with
`new_password` after a recent password sign-in. The server requires a
different password, revokes existing sessions and clears the setup requirement.
The user signs in again with the new password.

Admins can change a staff account's `name`, `email`, or `role` with
`PATCH /admin/staff-accounts/{uid}` and a `request_id`. Role or email changes
require the affected account to sign in again. A different admin must make
changes to an admin's own role or email.

Admins can deactivate or reactivate a team account with
`PATCH /admin/staff-accounts/{uid}/active`. Supply a boolean `is_active` and
a `request_id`. Deactivation blocks sign-in and invalidates existing sessions.
Reactivation preserves the UID, profile, role and audit history. An admin
must use a different admin account to deactivate their own account.

In the app, open **Manage staff accounts** from the admin landing page.
The history button opens the newest changes first. The screen loads history
from the admin-only `GET /admin/staff-accounts/history` endpoint.

Creation, edits and status changes record the actor, target and before/after values in
`staff_account_history`. Temporary passwords are omitted from API responses
and audit records. Password setup and audit records are private to the backend.

The development merge combines package management/history with the guarded
membership workflow. `/purchases` creates a Pending selection, and
`/purchases/current` displays that selection or its verified membership terms.
Both selection endpoints share the same snapshots and overlap guard; existing
historical purchase snapshots remain readable. Admin-created packages use the
shared `packages` catalog and preserve calendar-month durations.
