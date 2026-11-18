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

Project: `fitnep-88908`. A read on 18 November 2026 returned
`404 CONFIGURATION_NOT_FOUND` for the Firebase Auth configuration, so real recovery
is awaiting Authentication initialization.

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

No development-project Auth settings, Functions or rules have been changed by
these local commits. The exact Figma logo asset is pending an original export or
file access; the existing text wordmark remains in use.

## Sessions and protected access

Firebase password reset revokes refresh tokens, but an already-issued ID token
can remain cryptographically valid until expiry. Every protected callable must
use `requireValidSession(request)` from `functions/src/session.cjs`. It verifies
the bearer token with Admin SDK `verifyIdToken(token, true)` and checks that the
verified UID matches the callable identity. Revoked, disabled and expired sessions
are refused; a verifier outage denies access with a retryable error.

`checkSession` exposes this verification for US 1's shared session lifecycle:
call it before exposing protected state, on resume and when a protected request
fails. On `unauthenticated`, sign out and invalidate the team's sensitive state
providers. Network failures must not be treated as verified sessions. Visible
sign-out on other devices depends on that US 1 integration; this change provides
the recovery-side cleanup and server enforcement, not a competing login/session UI.

The current Firestore rules deny **all direct client access**, including fresh
sessions. Current protected access is through trusted Functions. These rules are
not a finished catalog/user/profile access policy: review this shared contract
before deployment, and add future direct access only with appropriate authorization
and revocation enforcement. Admin SDK operations bypass Firestore rules, so each
business callable still needs its own resource/role checks after session validation.

## Verification

```powershell
flutter analyze
flutter test
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
denial. Local validation also passed 19 Flutter tests, four server unit tests,
the analyzer and the Android debug build. Firestore uses port 18080 locally to
avoid another service already using port 8080.

Before marking US 2 Done, record real mailbox delivery, actual code expiry, public
enumeration behavior, configured server-policy rejection, real email-to-app link
behavior, and two-device sign-out with US 1's session lifecycle connected. Evidence
and sprint planning stay in `D:\fitnep_plan` outside the application repository.
