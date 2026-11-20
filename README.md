# FitNEP

Flutter nutrition and fitness app for Android and iOS.

## Current implementation

The app now initializes the shared Firebase development project and opens a
FitNEP welcome screen with navigation. Startup has loading and retry states.
Riverpod provides shared Firebase Auth, Firestore and Functions dependencies.

US 2 password recovery now has email requests, reset-link/code verification,
new-password forms, Firebase password-policy checks and local sign-out. Revoked
sessions are also checked on app resume and every 30 seconds in the foreground. The
recovery screens follow the supplied auth screenshots. Login/registration (US 1)
belong to the authentication teammate; package selection and the remaining flows
are still to be integrated. The original Figma logo, a shared Inter/orange/navy
theme, and Android/iOS launch screens are now integrated. See
[branding](docs/branding.md) for source references and platform validation.

See [password recovery integration](docs/password-recovery.md) for route names,
Firebase setup, session enforcement and verification.

Dilochan's contribution adds the admin client list/profile/audit screens,
client home, notifications and routes to related diet plans, conversations,
tasks and payments. Admin data currently comes from the local mock datasource.
The shared router starts at welcome and retains all recovery and feature routes;
US 1 must connect authenticated navigation and trusted role claims.

The notification API base URL defaults to empty because this Spark project has
no deployed notification backend. The screens show a configuration error until
a backend is explicitly supplied:

```powershell
flutter run -d <android-device-id> --dart-define=API_BASE_URL=https://api.example.com/
```

Notifications use `GET /notifications`, `PATCH /notifications/{id}/read` and
`PATCH /notifications/read-all`. Requests read the current shared Firebase ID
token, and the server derives recipient identity from that verified token.
Sign-out clears cached notifications and destination records. Diet-plan,
conversation, task and payment record endpoints remain feature integrations;
the notification backend does not implement those record APIs yet.

The TypeScript notification backend and recovery callable are combined in
`functions/`; both use revocation-aware Admin SDK verification. They are retained
for local emulator testing. See [backend setup](functions/README.md) for API
schemas, custom claims, workflow hooks, indexes and tests. No deployment or
billing change is part of this merge.

## Workspace and tools

Repository: `D:\fitnep\fitnep`.
Installed SDK: Flutter 3.47.5 / Dart 3.13.4 at `D:\flutter`.
Use a compatible SDK matching `pubspec.yaml`.

```powershell
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

iOS builds and device validation require macOS and Xcode.
Firebase client configuration currently supports Android and iOS.

## Shared Firebase development project

Project ID: `fitnep-88908`.
Console: https://console.firebase.google.com/project/fitnep-88908/overview

| Platform | Identifier | Firebase app ID |
| --- | --- | --- |
| Android | com.example.fitnep | 1:1005066655980:android:439e90e7ff1e252483edc9 |
| iOS Runner | com.example.fitnep | 1:1005066655980:ios:b66d19dd781a157b83edc9 |

Client configuration is in:
- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

These files identify the client applications and are versioned for reproducible
team setup. They are not server credentials. Keep private service-account keys,
signing credentials and local secrets out of the mobile app and Git history.

The Android Google Services plugin and iOS Runner plist resource are configured.
Kotlin incremental compilation is disabled to support a Windows workspace and
Pub cache on different drives.
Android builds also limit Gradle workers and compile Kotlin in the Gradle JVM
to keep memory use suitable for development laptops.

For the first full Android build on a memory-constrained Windows machine, the
following runtime settings can reduce native compiler pressure. They apply only
to the current shell/build and are restored afterwards:

```powershell
$previousFitNepJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
  $env:JAVA_TOOL_OPTIONS = "$previousFitNepJavaOptions -XX:ActiveProcessorCount=2 -XX:HeapBaseMinAddress=8G".Trim()
  flutter build apk --debug
} finally {
  $env:JAVA_TOOL_OPTIONS = $previousFitNepJavaOptions
}
```
Firestore databases, authorization rules, Functions deployment and enabled Auth
providers are separate server setup tasks; app registration does not create them.

Invite teammates to the Firebase project through their own Google accounts.
Email/Password, enumeration protection and the development password policy are
enabled. The project will remain on Spark. Password recovery uses Firebase Auth
directly; the locally tested Functions example is optional and is not deployed.
Agree the shared Firestore schema, region and server rules before implementing
package operations.

## Shared code

- `lib/app/app.dart`: app setup and startup boundary.
- `lib/app/routes/`: named routes and router lifecycle.
- `lib/app/theme/`: shared FitNEP theme and palette.
- `lib/core/services/firebase_providers.dart`: initialization and injectable SDK dependencies.
- `lib/shared/widgets/`: page layout, branded startup feedback and original logo.
- `lib/features/`: existing feature folders; use the files needed for each story.

Read Firebase SDK providers after initialization completes. Override the providers
in feature tests instead of connecting widget tests to the live project.

The recovery callable uses `us-central1`; the notification API and workflow hooks
use `asia-south1`. The shared callable SDK defaults to `us-central1` and can be
configured for a different callable region:

```powershell
flutter run -d <android-device-id> --dart-define=FIREBASE_FUNCTIONS_REGION=<deployed-region>
```

## Checks and cooperation

```powershell
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --concurrency=1
flutter build apk --debug
git diff --check
```

GitHub Actions runs format, analysis and widget tests for the shared branches.
The widget tests check startup gating, recovery navigation, form validation,
retry, reset completion and keyboard use with larger text on a small display.
Functions unit/emulator tests cover reset-code replay, changed credentials and
revoked-session access. Live Android recovery, mailbox delivery, actual provider
expiry, equivalent public email responses and rejection of old credentials and
multiple session tokens were verified on 18 November 2026. The login handoff and
iOS checks remain pending. Protected-data features need authorization and
revocation rules designed for Spark before integration; see the recovery
document for the evidence and its limits.

Use personal work branches and PR into `development`. Include story IDs,
acceptance evidence, tests and any shared Firebase/schema changes in the PR.
Use the agreed release branch and GitHub Releases for tested APK prereleases;
do not commit build output.

The four-day work plan, Firebase teammate handoff and release-notes template are
maintained separately in `D:\fitnep_plan`.

The project budget is zero. No payment gateway, real charges, paid hosting or
Firebase billing upgrade is required. [Run the free local demo](docs/free-demo.md)
to complete the client selection → manual admin verification → Active journey.

US 9 package catalog, Pending selection and membership screens are implemented
at `/client/packages`, with protected server operations and verified-payment
activation. Local emulator checks cover ownership, snapshots, revoked sessions
and concurrent date overlap. Manual admin verification is available without a
gateway. The local demo includes test login and catalog data; the normal app's
live catalog and US 1 login handoff remain team integration dependencies.
See [package setup](docs/packages.md).

The zero-budget package demo passed on the connected Android phone, including
manual admin approval, saved Active dates and client approval denial. The final
checks passed 77 Flutter tests, 18 backend unit tests and nine package emulator
tests. See [demo setup and evidence](docs/free-demo.md).

The Prajwol/Dilochan integration passed 70 Flutter tests, 18 backend unit tests,
21 combined Firebase emulator checks, formatting, the analyzer and the Android
debug APK build. Local backend checks used Node 24; the declared runtime and CI
use Node 22. These checks did not deploy Functions or change Spark billing.
