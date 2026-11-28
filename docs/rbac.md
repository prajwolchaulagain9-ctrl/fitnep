# FitNEP role-based access control

## Existing architecture and integration

FitNEP is one Flutter application using Riverpod, GoRouter, Dio, Firebase
Authentication (email/password, Google sign-in and the existing email OTP flow),
Firestore, and a TypeScript/Express backend. The Firebase HTTPS function and the
Node serverless adapter use the same backend services and authorization policy.

Before this change, Client/Dietitian/Admin route guards and selected backend
checks existed, but they read token role claims; Staff was missing. The Client
dashboard and package workflows existed. Staff/Dietitian/Admin home dashboards
have now been added around those workflows. The existing admin client and audit
pages previously used an in-memory datasource. Their production provider now
uses authenticated backend APIs. The local datasource remains only as an
explicit test fixture; application code does not select it.

The login, signup and OTP page layouts are preserved. Successful authentication
now enters the appropriate role dashboard. No privileged role selector is added
to signup.

## Canonical account schema

Each active FitNEP account is represented by `users/{FirebaseAuthUID}`:

| Field | Source |
| --- | --- |
| `full_name`, `email` | Firebase identity at provisioning; authenticated own-profile name edits |
| `role` | Exactly one of `client`, `staff`, `dietitian`, `admin` |
| `account_status` | `active` or `inactive`, changed by authorized administration |
| `role_revision` | Server-managed version, advanced on role/status changes |
| `created_at`, `updated_at` | Server-generated Firestore timestamps |
| `deactivated_at`, `deactivation_reason` | Server-owned optional deactivation details |

Firebase-only accounts have no business access until their account record is
provisioned. The authenticated session API provisions new users as Clients.
Existing trusted roles can be imported once from the Admin SDK's **current**
Firebase identity record when there is no account document. Existing malformed
account documents fail closed. Token role claims never authorize an API request.

The server also writes `account_access/{uid}` with only a revision and timestamp,
atomically with account provisioning and role/status changes. This is a change
signal, not a source of role authority. Direct Firestore profile reads remain
closed, including to the profile owner.

Own-profile edits accept only a name. Role/status/permission edits to an own
profile are denied. Administrative APIs also deny an administrator's changes to
their own role/status. Every privileged write validates the acting admin's
current account again inside the transaction.

## Central policy and dashboards

`functions/src/authorization_policy.ts` is the security policy.
`lib/shared/role_permissions.dart` is its presentation equivalent.
A test compares the two permission maps. `AuthorizationService.hasPermission`
controls menus/actions, and `permissionForRoute` supplies reusable route guards.

| Role | Dashboard and permitted work |
| --- | --- |
| Client | Existing Client home, own profile, notifications, membership/packages, privacy preferences, own records and assigned diet plans |
| Staff | Staff home, own profile/notifications/workflow records, assigned client contact details |
| Dietitian | Dietitian home, own profile/notifications, assigned client details, consented private records, create/edit plans for assigned active clients |
| Admin/CEO | Admin home, user/role/status/care-team management, existing client management, packages/payment approvals/history and audit logs |

Staff cannot access private health/photo/activity records under FitNEP's existing
privacy policy. Admin status does not grant a bypass to clients' private records.
These are deliberate business restrictions; granting private record access to
Staff would require a separate consent/assignment policy change.

## Backend enforcement and record access

Each protected API request verifies the Firebase ID token with revocation checks,
reads the current trusted account from Firestore, rejects invalid/inactive
accounts, checks the centralized endpoint permission, and then checks the
requested record. There is no role TTL, local role store or token-claim fallback
after account provisioning. Protected business data additionally requires a
verified email. OTP/session/profile provisioning remain reachable during signup.

* Notifications are queried and mutated only for the verified caller UID.
  Unauthorized or unavailable notification IDs return a generic 403
  `permission-denied` response without disclosing existence.
* Private records use `client_records/{clientId}/{category}`. Clients may read
  their own records. Dietitians must have an active, current assignment and
  explicit consent for that category. Private record authorization and consent
  reads occur within the Firestore transaction before data is read/written.
* `client_assignments/{clientId}` stores an assigned dietitian, Staff IDs and
  role revisions. Both the client and care-team account versions must match.
  Role/status changes invalidate old grants; an admin must renew assignments.
* Assigned-client lists query only assignments for the current actor. Staff get
  contact details, not financial or health data.
* Diet plan reads/writes validate the client and the current assignment.
  Creating/updating a plan derives the actor UID/role on the server.
* Message/conversation/task/payment destinations validate ownership/participants.
  Business-authorized administrators may read payment records.
* Admin client profiles return an explicit whitelist of business fields.
  Missing optional profile information stays absent; fictional birth dates,
  payments or client records are not generated.

The Express error boundary returns HTTP 403 with
`{"code":"permission-denied","error":"You do not have permission to access this feature."}`.
Permission matching follows Express's case-insensitive routes, optional trailing
slash and implicit `HEAD` handling. Captured record IDs retain their original
case. Each registered RBAC handler also checks its server-owned route policy;
an unconfigured handler fails closed before reading storage. Diet-plan reads
require the existing diet-plan permission before owner/assignment checks, so a
Staff contact assignment does not grant access to plans.
Dio consumers show a clear message and refresh current authority. Record denials
remain visible while other authorized panels, such as diet-plan tools, remain
usable.

## Live role changes

Role/status changes update the account and audit entry atomically. Every request
begun after the change reads the new account, even with the same old ID token.
Existing Firebase revocation checks still protect password-reset/signout sessions.

Flutter observes the self-only change signal and fetches the current account
through the revocation-aware API. Cached or locally pending signal snapshots
never authorize screens. A security change clears data cached for the
previous identity/role, closes dialogs, refreshes menus and redirects forbidden
screens to the new dashboard. Permission-denied responses refresh the account
without replaying the denied action when authority is unchanged. The existing
session observer also refreshes authority on resume and during its 30-second
foreground checks. Connection/verification failures display a retryable message
and hide protected content.

## Auditing

`audit_logs` is backend-owned and append-only to application users. Denied API
operations record an auto-generated ID, verified UID/current role when available,
attempted permission, resource, affected record ID, `DENIED`, server timestamp
and a bounded reason. Successful role/status/assignment changes record the actor,
target, previous/new values and a server timestamp in the same transaction.

No passwords, bearer tokens, raw URLs or request bodies are logged. Resource
names come from server policy, and credential-like record IDs are discarded.
If audit persistence
is unavailable, a denied API operation fails closed with 503.

Firestore rules deny ordinary direct writes to roles, business data and audits.
**Direct Firestore rule denials do not execute the Express audit writer.**
Production operators need a separate platform audit integration for those bypass
attempts, such as supported Firebase/Google Cloud audit-log exports, and must
verify coverage of their SDK/REST traffic. Firestore rules cannot create audit
documents as a side effect.
The custom audit collection covers requests through the application API.

## Deployment and migration

This implementation has been validated locally. Production role data, rules and
the backend must be deployed before the feature can be used against live data.
Create the default Firestore Native database with closed production rules before
running the migration. The Spark deployment gate below describes the external
hosting work required before public rollout.

1. Build the backend: `npm --prefix functions run build`.
2. With trusted server-side Firebase Admin credentials, preview migration:
   `node functions/scripts/migrate-rbac.cjs --project=fitnep-88908`.
3. Review the counts and invalid account IDs. Apply intentionally with the same
   command plus `--apply`. The migration preserves existing valid roles,
   creates missing account metadata and writes migration audit records.
   Invalid authoritative roles require operator review.
4. If no active admin exists, a trusted operator can bootstrap one existing,
   enabled Firebase account with `--apply --bootstrap-admin=<CEO_FIREBASE_UID>`.
   The script refuses bootstrap when an active admin already exists.
5. Deploy `firestore.rules` and the existing Firestore indexes using
   `firebase deploy --only firestore:rules,firestore:indexes --project fitnep-88908`.
6. Deploy the updated API and callable authentication helpers. To retain Spark,
   the existing Node serverless host can export the Express handler returned by
   `createFitnepApi()` from `functions/lib/api_factory.js`. Initialize it once
   per host instance and mount it at the configured API base URL. Firebase Admin
   credentials stay in that host's secret/managed-identity environment.
   Using Firebase Functions instead requires an eligible billing plan; the work
   here does not change billing or deploy live services.
7. Set Flutter's `API_BASE_URL` (or the corresponding dart-define configuration)
   to the deployed HTTPS API root. Retain the existing Google/OTP configuration.
8. Review care-team assignments after migrating roles. Legacy revision-zero
   assignments remain valid only for unchanged accounts. Renew assignments after
   a role/status change. Configure platform Data Access Audit Logs as described
   above, then perform a live account/device smoke test.

No destructive database reset is required. No service credentials belong in
Flutter assets or source control.

## Phase 1 review and Spark deployment gate (2026-11-22)

The live-project investigation confirmed the Android configuration targets the
active `fitnep-88908` project. Billing is disabled, the Firestore database list
is empty, no active `cloud.firestore` rules release exists, and the Cloud
Functions API is disabled. No external API URL is configured. Phase 1 changes
and tests do not create live accounts, deploy services, enable APIs or billing,
or supply a pretend backend URL.

The current emulator-only Flutter startup route is `AppRoutes.adminClients`.
This requests the admin client list as a testing entry point; it does not grant
an admin role. Signed-out users are redirected to the demo entry and non-admin
users remain guarded. The edit's authorship/intent is not recorded in Git. It
was preserved, and a Flutter regression verifies that every non-admin role is
denied before client-list data is requested. Production startup still uses the
welcome route.

An approval-gated Spark rollout requires:

1. Choose the default Firestore database region, create it in production mode,
   and deploy the reviewed rules/indexes. Preview account migration with trusted
   credentials, review the real CEO UID, and apply only approved provisioning,
   role changes and care assignments. Ordinary users cannot choose roles.
2. Identify the user's existing external Node host and its eligible plan. Mount
   `createFitnepApi()` at a verified HTTPS root with server-side Firebase Admin
   credentials, current-account checks and audit persistence. Validate the
   chosen runtime; the package requests Node 22 but local emulators used Node 24.
3. Expose and validate the existing numeric OTP callable handlers on that host.
   `createFitnepApi()` alone does not mount them. Set both `SIGNUP_OTP_SEND_URL`
   and `SIGNUP_OTP_VERIFY_URL`, preserve the callable protocol, revocation checks,
   server-side OTP state, rate limits and Firebase email-verification update.
   Brevo credentials/hash secrets belong only in the host's secret store.
4. Replace Firebase-hosted workflow triggers with a trusted, idempotent external
   execution/retry mechanism for notifications and package payment activation.
   Mounting Express alone does not execute Firestore triggers. This host wiring
   remains deployment preparation work and must be tested before public rollout.
5. Review abuse protection, quotas, server monitoring and direct Firestore-denial
   logging. API denials already append safe audit records. Direct rule denials
   require platform logging coverage checks and an approved export pipeline;
   they cannot create custom audit documents from rules. Google documents that
   audit identity data can contain JWT header/payload, so exports to application
   audits must whitelist fields and omit that token data. Review any logging or
   export charges before enabling additional services.
6. Supply the verified `API_BASE_URL` and OTP HTTPS URLs as Flutter compile-time
   defines, rebuild the Android app, and verify real Google/email/OTP login and
   all four roles on the device. An `.env` file alone does not configure Flutter.

Firestore's documented free quota covers one database, 1 GiB stored data,
50,000 document reads/day, 20,000 writes/day, 20,000 deletes/day and 10 GiB
outbound/month. Live role reads, listeners and audit writes consume this quota.
Firebase-hosted Cloud Functions, TTL deletion, backups/PITR, restore and clone
features require billing. On Spark, OTP expiration is already enforced by code;
do not enable TTL. External hosting and Brevo have their own limits and charges,
and a provider's free tier must permit this business application.

Sources reviewed: [Firestore quotas](https://firebase.google.com/docs/firestore/quotas?hl=en),
[Functions deployment](https://firebase.google.com/docs/functions/get-started),
[TTL](https://firebase.google.com/docs/firestore/ttl?hl=en), and
[Firestore audit logging](https://docs.cloud.google.com/firestore/native/docs/audit-logging?hl=en).

## Verification

* `flutter analyze --no-pub`: clean.
* `flutter test --no-pub`: **136 passed**, including the admin-entry regression.
* Backend TypeScript production compilation and test typecheck: passed.
* Backend API/Firestore/workflow and real callable revocation regression suite:
  **67 passed**. This includes the **55** unit/API/policy tests and the live
  local emulator integrations; these counts must not be added twice.
* Dedicated Firebase RBAC, role-change, record-ownership, audit-redaction,
  migration and serverless-adapter integration suite: **16 passed**.
* Package catalog/payment activation emulator suite: **11 passed**.
* Real password-reset/callable revocation emulator regression: **1 passed**,
  included in the 67-test suite.
* Real Firebase Auth/Firestore emulator suites exercise unchanged-token role
  changes, record ownership, consent, direct security-rule attacks, serverless
  adapter parity and migration/first-admin safeguards.
* The earlier Android debug APK build succeeded; output:
  `build/app/outputs/flutter-apk/app-debug.apk`.
  Phase 1 did not rebuild/configure the device APK or perform a live rollout.
* Package tests run in their own Node process, as in the existing package test
  script. Combining them with suites that delete the default Firebase Admin app
  caused a fixture collision; the separate final runs all passed.

The standard emulator command is:
`firebase emulators:exec --only auth,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:rbac:emulator"`.
During this task, existing emulators were preserved and isolated ports were
configured in the ignored local file
`.dart_tool/rbac-emulators/firebase.json`.
Phase 1 compiled tests into the ignored
`functions/.test-build/phase1-authorization-20261122` without deleting earlier
output, and used `.dart_tool/rbac-emulators/functions.json` for local trigger and
callable checks. No emulators remained running after the checks.

Live host deployment, platform audit-log configuration, live account migration
and device sign-in validation remain deployment steps, not emulator results.

## Created files (23)

- `functions/scripts/migrate-rbac.cjs`
- `functions/src/account_service.ts`
- `functions/src/api_factory.ts`
- `functions/src/endpoint_access.ts`
- `functions/src/rbac_http.ts`
- `functions/test/rbac_emulator.test.ts`
- `functions/test/rbac_policy.test.ts`
- `lib/shared/authorization_refresh.dart`
- `lib/shared/role_permissions.dart`
- `lib/features/admin/data/admin_datasource.dart`
- `lib/features/admin/data/admin_remote_datasource.dart`
- `lib/features/authorization/data/authorization_repository.dart`
- `lib/features/authorization/data/account.dart`
- `lib/features/authorization/account_session.dart`
- `lib/features/authorization/assigned_clients_page.dart`
- `lib/features/authorization/client_records_page.dart`
- `lib/features/authorization/profile_page.dart`
- `lib/features/authorization/role_home_page.dart`
- `lib/features/authorization/user_management_page.dart`
- `test/support/denied_permission_repository.dart`
- `test/support/empty_notifications.dart`
- `test/widgets/role_authorization_test.dart`
- `docs/rbac.md`

## Modified files (43)

- `docs/signup.md` (Spark deployment/TTL guidance only)
- `firestore.rules`
- `functions/package.json`
- `functions/src/auth.ts`
- `functions/src/authorization_policy.ts`
- `functions/src/demo_server.ts`
- `functions/src/domain.ts`
- `functions/src/firestore_private_records_store.ts`
- `functions/src/http_app.ts`
- `functions/src/index.cjs`
- `functions/src/index.ts`
- `functions/src/notification_service.ts`
- `functions/src/nutrition_record_access_service.ts`
- `functions/src/package_membership_service.ts`
- `functions/src/package_service.ts`
- `functions/src/privacy_preferences_service.ts`
- `functions/src/purchase_service.ts`
- `functions/src/signup_email_codes.ts`
- `functions/test/firebase_emulator_security.test.ts`
- `functions/test/auth-emulator.test.cjs`
- `functions/test/notification_security.test.ts`
- `functions/test/package_emulator.test.ts`
- `lib/app/routes/app_router.dart`
- `lib/app/routes/app_routes.dart`
- `lib/app/routes/route_access_gate.dart`
- `lib/shared/api_client.dart`
- `lib/shared/api_client_provider.dart`
- `lib/features/admin/data/admin_local_datasource.dart`
- `lib/features/admin/data/client_model.dart`
- `lib/features/admin/data/admin_repository_impl.dart`
- `lib/features/admin/data/audit_log_entity.dart`
- `lib/features/admin/data/client_entity.dart`
- `lib/features/admin/client_list_controller.dart`
- `lib/features/admin/client_profile_controller.dart`
- `lib/features/admin/pages/audit_log_page.dart`
- `lib/features/admin/pages/client_profile_page.dart`
- `lib/features/admin/widgets/audit_log_tile.dart`
- `lib/features/authentication/password_reset_session_observer.dart`
- `lib/features/client/pages/client_home_page.dart`
- `test/app/routes/app_router_notification_test.dart`
- `test/features/admin/presentation/pages/client_list_page_test.dart`
- `test/widgets/authentication_flow_test.dart`
- `test/widgets/signup_flow_test.dart`

Generated build output and the ignored local emulator configuration are outside
this source/test/documentation manifest.
