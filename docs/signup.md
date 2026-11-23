# Signup, Google sign-in and Brevo email verification

`/signup` uses the same `RecoveryPage` layout and `FitNepWordmark` as Login and
Forgot Password: white background, orange buttons, rounded fields and the shared
footer. It collects name, email, age, password and confirmation. Firebase creates the
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

Verified accounts without a `role` claim enter as clients. Existing signed
admin and dietitian claims retain their access. Unsupported assigned roles are
rejected; no setup callable or client-written role is needed. The API verifies
the Firebase token with revocation checks and applies the same client default.

Clients enter `/client/home` after sign-in and use **Packages** to choose a
plan. A successfully saved selection returns them home, where they can see its
pending payment status. Home links to membership, packages, notifications and
privacy preferences. Failed saves keep the client on package selection and
reuse the request ID on retry.

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

## Consent and email verification

Email signup collects age with the other registration fields. Completing the
form opens the Privacy Policy. The acceptance checkbox unlocks at the end,
and clients under 18 also confirm guardian permission. Accepting creates the
account and opens email verification by code or link. The app keeps the
pending consent in secure device storage under the new account's UID.
After verification, the server saves the consent and its date in Firestore
before opening Client Home. New Google sign-ins and clients resuming without a pending consent
record complete the age and policy review after Firebase verifies their email.

Unverified email/password users also return to verification on login and restored
sessions. Password recovery remains accessible.

With the hosted API configured, the app requests a six-digit code from the
backend. The app sends a Firebase verification link if the code endpoint is
missing or reports that delivery is unconfigured. If delivery fails for another
reason, users can choose **Send a verification link instead** when the resend
cooldown is clear. Set the Flutter define `SIGNUP_EMAIL_OTP_ENABLED=false` to
start with a link. After opening it, return to the app and tap
**I verified my email**. The app reloads the Firebase user and checks the
refreshed token before continuing.

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
implementation uses the hosted Render API or Firebase callable functions.
The backend verifies codes and marks the Firebase account's email as verified.

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
   deny-all rules. On Spark, do not enable Firestore TTL: TTL deletion requires
   billing. The callable already enforces expiration and preserves the hourly
   rate-limit window without TTL. An approved future paid-plan rollout can use
   TTL on `expires_at` for cleanup; an external cleanup job must preserve that
   full rate-limit window.
6. Supply callables in `us-central1`, or configure the serverless host URLs
   described below. The shared Functions provider uses
   `FIREBASE_FUNCTIONS_REGION`; the recovery callable shares this region.

For local USB testing, the Functions emulator runs the OTP handlers and keeps
OTP records in the local Firestore emulator. See the Render setup below for the
shared backend.
Before public rollout, configure App Check or equivalent anti-abuse protection
in addition to per-account throttling. New Firebase accounts do not receive
trusted role claims from this flow. The API treats verified accounts with no
assigned role as clients and requires signed claims for privileged access.
A Flutter route guard alone is not data authorization.

## Existing Render service

Use the `API_BASE_URL` in `config/development.example.json`. The hosted app
requests codes at `/auth/signup/otp/send`, verifies them at
`/auth/signup/otp/verify`, and records consent at `/auth/privacy`.

On the existing `fitnep-api` service, set `SIGNUP_EMAIL_OTP_ENABLED=true`,
`BREVO_API_KEY`, a verified `BREVO_SENDER_EMAIL`, and a stable random
`SIGNUP_OTP_HASH_SECRET` of at least 32 characters. `BREVO_SENDER_NAME` is
optional. Keep credentials in Render's environment settings. Manually deploy
`development` and verify its commit at `/healthz` before testing email delivery.
See [Hosted API setup](hosted-api.md) for deployment details.

For a separate Firebase callable setup, configure `SIGNUP_OTP_SEND_URL` and
`SIGNUP_OTP_VERIFY_URL` together if overriding the default callable URLs. Use
`SIGNUP_PRIVACY_URL` for an independently hosted consent callable. The app and
backend must use the same Firebase Auth project and Firestore database.

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
