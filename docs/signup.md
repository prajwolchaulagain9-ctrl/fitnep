# Signup, Google sign-in and Brevo email verification

`/signup` uses the same `RecoveryPage` layout and `FitNepWordmark` as Login and
Forgot Password: white background, orange buttons, rounded fields and the shared
footer. It collects name, email, password and confirmation. Firebase creates the
email/password account and owns its credentials. The display name is saved on
the Firebase user; profile completion can recover a failed name update later.
Firebase enforces its configured server password policy in addition to the
form's eight-character minimum. Successful registration remembers the session.

Both Login and Signup offer **Continue with Google**. Android/iOS use
`google_sign_in` to obtain an ID token, then Firebase `signInWithCredential`.
Cancellation leaves the form available. A Google account's first login also
creates its Firebase account. Existing accounts retain their existing sign-in
method; accounts are never linked automatically. The Google option follows
Login's Remember Me choice and remembers the session from Signup.

## Google configuration

Google is enabled in Firebase Authentication. The Android and iOS client files
have been refreshed from Firebase with their OAuth client IDs. This workstation's
Android debug SHA-1 and SHA-256 fingerprints are registered, and the iOS callback
URL scheme is configured. For other signing keys or configuration changes:

1. Keep Google enabled in Firebase Authentication > Sign-in method.
2. Register Android debug/release SHA-1 and SHA-256 signing fingerprints for
   `com.example.fitnep`; download the updated `android/app/google-services.json`.
3. Download the updated `ios/Runner/GoogleService-Info.plist`. It must include
   `CLIENT_ID` and `REVERSED_CLIENT_ID`. Set `GIDClientID` in
   `ios/Runner/Info.plist` to `CLIENT_ID` (or provide `GOOGLE_IOS_CLIENT_ID` below).
   Add `REVERSED_CLIENT_ID` as a second URL scheme in `ios/Runner/Info.plist`,
   preserving the existing `fitnep` recovery scheme.
4. If needed, supply `GOOGLE_WEB_CLIENT_ID` (OAuth **Web application** client ID,
   used as Android's server client ID) and `GOOGLE_IOS_CLIENT_ID` via
   `--dart-define-from-file=config/development.json`. Copy the example first.
   OAuth client IDs are public identifiers; never put a client secret here.

The app's Firebase platform setup currently supports Android/iOS. Web has the
Firebase popup branch, but needs its own Firebase configuration before use.

## Email verification and consent after signup

Email/password signup creates a Firebase account and asks the user to verify
their email. After verification, clients enter their age and accept the current
Privacy Policy. Clients under 18 confirm guardian permission. The app opens
after Firestore confirms the record was saved. Google accounts whose email is
already verified go straight to the privacy step.

Unverified email/password users also return to verification on login and restored
sessions. Password recovery remains accessible.

The verification screen defaults to a Firebase email link when no code
endpoints are configured or when `SIGNUP_EMAIL_OTP_ENABLED=false`. It also uses
the link when the configured send
endpoint returns 404. After opening the link, return to the app and tap
**I verified my email**. Verification reloads the Firebase user and checks the
refreshed token's `email_verified` claim before protected navigation.
When code endpoints are configured and available, the screen accepts the
six-digit code and reuses it until expiry or an explicit resend.

Local email/password signup uses a test verification link from the Auth
emulator. The built-in demo accounts are already verified.

The Google button uses Google's official G asset from
`https://developers.google.com/static/identity/images/g-logo.png`.

Two backend callables in `us-central1` are ready for configuration:

- `sendSignupEmailCode`: no client email/UID parameters; returns
  `{ "resendAfterSeconds": 60 }` after delivery.
- `verifySignupEmailCode`: accepts `{ "code": "123456" }`; returns
  `{ "verified": true }` after the Firebase Admin update.

Both revalidate the bearer token with revocation checking and read the current
email from Firebase Admin. Brevo uses `POST https://api.brevo.com/v3/smtp/email`.
Codes expire after ten minutes, are stored as HMAC digests bound to UID/email,
and are consumed atomically. Each code permits five failed attempts; each UID
permits five sends per hour. Resend replaces the old challenge. Failed delivery
invalidates the challenge and still counts toward limits. A temporary Admin
update failure preserves a correct code for retry. No OTP/password/API key is
written to logs or app storage.

## Trusted OTP execution

Brevo hosts the transactional email delivery API, so no dedicated email server
is needed. For custom six-digit signup verification, code generation, attempt
limits, verification and the Firebase Admin update must run in a trusted
environment. The Brevo API key cannot be bundled into the Flutter app. This
implementation uses Firebase callable functions; serverless execution is enough
and does not require maintaining a dedicated server. Brevo email delivery alone
does not verify the code or mark the Firebase account's email as verified.

Firebase's built-in email verification links can use Firebase's hosted Auth
service without this custom OTP backend, but that changes the requested numeric
code flow into a link flow.

## Function configuration

1. Verify your sending address/domain in Brevo and obtain a transactional API key.
2. Copy `functions/.env.example` to `functions/.env`. Set a verified
   `BREVO_SENDER_EMAIL`, `BREVO_SENDER_NAME`, and server
   `SIGNUP_EMAIL_OTP_ENABLED=true` only when ready.
3. For the local emulator, copy `functions/.secret.local.example` to
   `functions/.secret.local` and enter `BREVO_API_KEY` and a cryptographically
   random `SIGNUP_OTP_HASH_SECRET` of at least 32 characters. These files are
   ignored by Git. Emulator calls with a real Brevo key send real emails.
4. For future Firebase hosting, these secrets are declared as Secret Manager
   parameters. Configure them with `firebase functions:secrets:set BREVO_API_KEY`
   and `firebase functions:secrets:set SIGNUP_OTP_HASH_SECRET`.
5. Configure Firestore. `signup_email_codes` is server-only under the existing
   deny-all rules. Enable Firestore TTL on `expires_at` for cleanup; expiration
   is enforced by the callable even before TTL deletion. The TTL timestamp also
   preserves the full hourly rate-limit window.
6. Supply callables in `us-central1`, or configure the serverless host URLs
   described below. The shared Functions provider uses
   `FIREBASE_FUNCTIONS_REGION`; the recovery callable shares this region.

The shared project remains on **Spark**. Firebase Auth stays live. The OTP runtime
and records run locally for USB testing until the existing serverless host is
configured. No billing plan is changed.
Before public rollout, configure App Check or equivalent anti-abuse protection
in addition to per-account throttling. New Firebase accounts do not receive
trusted admin/dietitian/client role claims from this flow. Protected data APIs
must enforce the Firebase `email_verified` claim server-side when the OTP phase
is enabled; a Flutter route guard alone is not data authorization.

## Existing serverless host

Set `SIGNUP_OTP_SEND_URL` and `SIGNUP_OTP_VERIFY_URL` to public HTTPS endpoints in
`config/development.json`. Both must be configured together. The callable client
attaches the current Firebase ID token. The host must validate it, derive UID and
email server-side, persist OTP records atomically and return the Firebase callable
protocol (`result` or `error`). Keep Brevo and Firebase Admin credentials in the
host's secret store. Provider and project details are needed before deployment.

The default app saves the entered age, policy version and server timestamp in
the signed-in user's Firestore consent record. Set up the default Firestore
database and publish the project's Firestore rules before distributing the
build. For an independently hosted privacy callable, set `SIGNUP_PRIVACY_URL`
to its HTTPS URL. The app and any email-code backend must use the same Firebase
Auth project and Firestore database.

## Local Samsung USB test

The helper uses the operator's Firebase CLI login through a temporary private
credential file and removes the file on normal exit. Firebase Auth is live;
Functions and OTP records are local. Real Brevo keys send real email.

```powershell
npm --prefix functions run build
node functions/scripts/start-otp-local.cjs
```

In another terminal, launch the connected phone with the local endpoint:

```powershell
& "$env:LOCALAPPDATA/Android/sdk/platform-tools/adb.exe" -s RZCX70QNPDR reverse tcp:5001 tcp:5001
flutter run -d RZCX70QNPDR --dart-define=FIREBASE_FUNCTIONS_EMULATOR_HOST=127.0.0.1
```

The host is used exactly, with automatic Android emulator mapping disabled.
Use `10.0.2.2` explicitly for an Android emulator. The override and cleartext
allowance apply to debug builds only. Keep the runtime and USB connection active
during local OTP testing. Permanent delivery requires the serverless host.
Google sign-in uses Firebase directly and does not depend on the local runtime.

Verification:

```powershell
flutter analyze --no-pub
flutter test --no-pub
npm --prefix functions run build
npm --prefix functions test
```

Automated tests use isolated authentication/mail doubles. Live signup, Google
account selection, Brevo delivery and iOS devices require configured credentials
and separate device validation.
