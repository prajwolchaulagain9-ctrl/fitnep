# FitNep Firebase notification backend

This folder contains the mobile application's Firebase Cloud Functions backend.
It exposes authenticated HTTPS APIs for the Flutter app; it does not contain a
website or browser UI.

The shared project stays on **Spark**. These Functions are local emulator
implementations; they are not deployed. Cloud Functions deployment requires a
billing-enabled project and is outside the agreed scope. The Flutter API URL
defaults to empty until a supported backend is supplied.

## Firebase project and runtime

- Project: `fitnep-88908`
- Region: `asia-south1`
- Runtime: Node.js 22
- Exported HTTPS function: `api`
- Recovery callable: `checkSession`, in `us-central1`
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

The token must have one of these trusted custom claims:

```json
{ "role": "admin" }
{ "role": "dietitian" }
{ "role": "client" }
```

Role claims must be assigned by a trusted administrative process using the
Firebase Admin SDK. Never allow the mobile app to assign or edit its own role.

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
storage is not implemented in this backend yet, so the gate fails closed until a
trusted assignment reader is configured.

## Notification APIs

- `GET /notifications`
- `GET /notifications/:notificationId`
- `PATCH /notifications/:notificationId/read`
- `PATCH /notifications/read-all`

Recipient identity is always derived from the verified token. Requests that
try to supply `recipient_id`, `recipientId`, `user_id`, or `userId` are rejected.
Unknown and unauthorized notification IDs both return `404` to avoid leaking
whether another user's notification exists.

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
npx --yes firebase-tools@latest emulators:exec --config firebase.json --project demo-fitnep --only firestore,functions "node --test --test-isolation=none --test-concurrency=1 functions/.test-build/test/workflow_trigger_emulator.test.js"
```

Firestore uses port 18080 in the shared configuration. The emulator-only
commands work without deploying to the Spark project.

The retained deployment script is outside the supported Spark workflow. No
Functions deployment or billing upgrade is part of this integration. A live
notification service needs a separately agreed hosting arrangement.
