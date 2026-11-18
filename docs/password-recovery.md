# Password recovery integration (US 2)

US 2 owns the forgot/reset screens and recovery service. Login and registration
remain US 1. No login, signup, dashboard, shop or chat screen is implemented here.

## Connect from login

Import `app/routes/app_routes.dart`, then call:

```dart
context.pushNamed(AppRoutes.forgotPassword);
```

The public recovery routes are `/forgot-password` and `/reset-password`. They stay
behind the existing Firebase startup boundary but must be accessible while signed
out. Authentication redirects introduced by US 1 must allow these paths.

The reset screen accepts a full HTTPS Firebase reset email link or its `oobCode`.
It checks the action's mode and delegates code validation, expiry, single use and
confirmation to Firebase Auth. The reset form never stores the password or code
in Firestore, secure storage or logs. Passwords are preserved exactly as typed.

On completion it signs out the current Firebase client, clears the recovery form
and returns to the welcome route. When US 1 supplies the agreed login route,
change the recovery success destination to that route. Do not create a second
login implementation for this integration. If local sign-out fails after the
reset, the screen offers a sign-out retry without reusing the consumed code.

Android and iOS register the `fitnep` URL scheme, for example:

```text
fitnep://auth/reset-password?mode=resetPassword&oobCode=<code>
fitnep://auth/forgot-password
```

Firebase email links do not automatically use this scheme. The initial supported
app flow is to copy the HTTPS reset link from the email and paste it into “Use a
reset link”. A one-tap return needs an approved HTTPS action handler/verified app
links. Default Firebase browser reset also works once Auth is configured. Native
recovery links, empty-email validation, invalid-link handling and fresh-request
navigation were verified on the connected Infinix X6817 (Android 12/API 31).
iOS requires macOS/Xcode validation.

## Firebase development setup

Project: `fitnep-88908`. Authentication was initialized on 18 November 2026.
Email/Password and enumeration protection are enabled. The development password
policy is enforced: at least eight characters, with uppercase, lowercase, a
number and a symbol. Coordinate policy changes with US 1; the Flutter service
reads the Firebase policy.

1. Open Firebase Console → Authentication → Get started; enable Email/Password.
2. Agree the password requirements with US 1 and set enforcement to **Require**.
   The Flutter service reads Firebase's current policy; it does not invent a
   separate minimum length or character policy. Server reset rejection is handled
   even when the client policy check passed.
3. Enable email enumeration protection. The app suppresses legacy missing/disabled
   account errors, but matching public API responses also require the server
   setting. Configure and test the reset email sender/template.
4. Create a synthetic account using a mailbox available for acceptance testing.
5. Review/deploy `checkSession` and the Firestore rules through the team's Firebase
   deployment process. Cloud Functions deployment requires Blaze billing.

The project remains on Spark by the owner's choice. `checkSession` is prepared
and tested locally; live Cloud Functions deployment remains pending Blaze.
The repository's Firestore rules have not been deployed to the development
project. The exact Figma logo asset is pending an original export or file access;
the existing text wordmark remains in use.

## Sessions and protected access

Firebase password reset revokes refresh tokens, but an already-issued ID token
can remain cryptographically valid until expiry. Every protected callable must
use `requireValidSession(request)` from `functions/src/session.cjs`. It verifies
the bearer token with Admin SDK `verifyIdToken(token, true)` and checks that the
verified UID matches the callable identity. Revoked, disabled and expired sessions
are refused; a verifier outage denies access with a retryable error.

The app's `PasswordResetSessionObserver` force-refreshes the shared Firebase Auth
session at startup/sign-in, on resume, and every 30 seconds in the foreground.
Revoked sessions are signed out and return to welcome; recovery routes remain
available and keep their confirmation. Background checks pause. Network errors
preserve the session and retry later. A refresh of an old session cannot sign out
a newer login, including a newer login for the same UID.

Forced refresh detects revoked refresh tokens; it does not authorize protected
operations. After deployment, use `checkSession` before exposing protected state
and when a protected request fails. On `unauthenticated`, sign out and invalidate
the team's sensitive state providers. Add cache/provider cleanup when US 1 and
the protected features introduce that state. No sensitive account cache exists
in the current app.

The repository's Firestore rules deny **all direct client access**, including fresh
sessions. Current protected access is through trusted Functions. These rules are
not a finished catalog/user/profile access policy: review this shared contract
before deployment, and add future direct access only with appropriate authorization
and revocation enforcement. Admin SDK operations bypass Firestore rules, so each
business callable still needs its own resource/role checks after session validation.

## Verification

```powershell
flutter analyze
flutter test --concurrency=1
npm --prefix functions ci
npm --prefix functions test
firebase emulators:exec --only auth,functions,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:emulator"
flutter build apk --debug
```

The Firebase CLI version used locally is 15.32.0. Functions target Node 22; emulator
checks need Java 21 or newer on PATH. This Windows workspace has Java at
`D:\studio\jbr\bin` and Flutter at `D:\flutter\bin`. Use the README's build JVM
settings on this memory-constrained machine. Emulator tests refuse live projects.

Unit/widget tests cover malformed input, generic confirmation, expired/used-code
error handling, matching passwords, password-policy rejection, delivery/verification
retry, duplicate taps, hidden fields, cleanup failure and startup/keyboard behavior.
The emulator check passed for real reset operations, replay, weak-password
rejection, old/new credentials, both old sessions and direct Firestore read/write
denial. Current local validation passed 25 Flutter tests, four server unit tests,
format checks and the analyzer. Firestore uses port 18080 locally to
avoid another service already using port 8080.

The live recovery test passed on Infinix X6817 on 18 November 2026, against the
working tree based on `1e48477` before the app observer was connected. The observer
and newer-login race guard are covered by the current unit/widget tests. The operator
confirmed mailbox delivery. It exercised the native request/reset UI, password
explanations, server weak-password rejection, used-code rejection, local sign-out,
a second native Firebase Auth instance, and a desktop session. Old credentials,
both captured old ID tokens (Admin SDK revocation verification) and the old
desktop refresh token were rejected; new credentials/token worked. Public reset
responses for existing and missing addresses matched. This verifies multiple
sessions, including the physical phone; a second physical phone was not tested.

An isolated unused reset code was valid at issue and during checks through
10:58:27 UTC. After the timed process was interrupted, a resumed check returned
`EXPIRED_OOB_CODE` at 12:43:35 UTC, 8,311 seconds after issue. This proves actual
provider expiry, without measuring the exact expiry time. The temporary expiry
account was removed. No expiry-test email was sent.

To repeat live acceptance deliberately using the Firebase CLI login:

```powershell
node scripts/live-recovery-harness.cjs --run
# In another terminal, with the Infinix connected:
D:\Android\SDK\platform-tools\adb.exe -s 0874637289000589 reverse tcp:8765 tcp:8765
flutter test integration_test/password_recovery_live_test.dart -d 0874637289000589 --dart-define-from-file=.dart_tool/live-recovery-defines.json
node scripts/live-reset-expiry-check.cjs --run
# If the timed expiry process is interrupted, check its saved fixture once:
node scripts/live-reset-expiry-check.cjs --resume
```

The live UI test is skipped unless `FITNEP_LIVE_RECOVERY_TEST` is explicitly
enabled. The harness only changes its own saved test account and refuses an
existing account without the matching fixture. Private credentials and action
codes, plus runtime results, stay in ignored `.dart_tool`; never commit them.
Expiry cleanup removes only its matching temporary fixture.

US 2 still needs the US 1 login entry/success-route integration, a reviewed live
protected-access deployment, and iOS validation. One-tap HTTPS email-to-app links
are pending; the supported paste-link flow is documented above. Keep the story
open until the remaining integration/security criteria are accepted. Sprint
planning stays in `D:\fitnep_plan` outside the application repository.
