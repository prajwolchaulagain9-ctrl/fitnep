# FitNep Firebase notification backend

This folder contains the mobile application's Firebase Cloud Functions backend.
It exposes authenticated HTTPS APIs for the Flutter app; it does not contain a
website or browser UI.

## Firebase project and runtime

- Project: `fitnep-88908`
- Region: `asia-south1`
- Runtime: Node.js 22
- Exported HTTPS function: `api`

After deployment, configure the Flutter app with:

```powershell
flutter run --dart-define=API_BASE_URL=https://asia-south1-fitnep-88908.cloudfunctions.net/api/
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
npm run deploy
```

Run the real Auth/Firestore security tests from the repository root:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
npm --prefix functions run build:test
npx --yes firebase-tools@latest emulators:exec --config firebase.json --project demo-fitnep --only auth,firestore "node --test --test-isolation=none --test-concurrency=1 functions/.test-build/test/notification_security.test.js functions/.test-build/test/firestore_notification_repository.test.js functions/.test-build/test/firebase_emulator_security.test.js"
```

Run all four workflow-trigger integration tests with the Functions emulator:

```powershell
$env:FITNEP_RUN_TRIGGER_TESTS = 'true'
npm --prefix functions run build
npm --prefix functions run build:test
npx --yes firebase-tools@latest emulators:exec --config firebase.json --project demo-fitnep --only firestore,functions "node --test --test-isolation=none --test-concurrency=1 functions/.test-build/test/workflow_trigger_emulator.test.js"
```

Firebase CLI authentication is required before serving/deploying:

```powershell
npx firebase-tools login
npx firebase-tools use fitnep-88908
npx firebase-tools deploy --only firestore:rules,firestore:indexes,functions
```
