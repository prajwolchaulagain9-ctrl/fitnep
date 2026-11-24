# Authentication and package flow fixes — 23 November 2026

Development runs prefer a healthy local backend and fall back to
`https://fitnep-api.onrender.com/`; release builds use Render by default. Firebase Auth
exchanges passwords and Google credentials; the API verifies the current
Firestore `users/{uid}` role, status and revision before authorizing data.
The existing account `prajwolchaulagain9@gmail.com` was explicitly authorized
as the first Admin/CEO and provisioned with audit records. Its password was not changed.

## Current journey

1. Welcome → login or signup.
2. Signup collects name, email, password, confirmation and explicit agreement to
   Terms and Conditions and Privacy Policy. Google signup also requires agreement.
3. Email accounts verify their email using Brevo OTP or the existing Firebase link fallback.
4. Clients complete any outstanding agreement, then enter `/client/packages`.
5. A package selection is stored as Pending before opening `/client/home`.
   If no packages exist, clients may enter the temporary dashboard without creating a membership.
6. Admin, dietitian and staff accounts enter their own permitted dashboards.
   Staff accounts that require a temporary-password change complete that first.

Age, goals and full personal onboarding are deferred. New consent records do
not invent an age or claim guardian permission. They save terms version 1,
privacy version 2 and `onboarding_pending: true`. Existing valid acceptance
records and age-based consent validation remain compatible.

## Fixes

- Login, signup and recovery share a compact layout and 40px auth logo.
  Password visibility and field configuration reuse `PasswordFormField`.
- Google remains visible on the connected phone without scrolling.
- Password recovery uses Firebase Auth directly, preserving the Sprint 1 flow
  without depending on the hosted recovery adapter's web API key configuration.
- The account check stays inside mounted session observers. An unnecessary
  token-provider invalidation caused account checks and splash screens to repeat;
  it was removed. Account checks have a bounded timeout and retry/sign-out controls.
- Cached Firestore snapshots do not erase an account already verified by the API.
  The existing owner-only `account_access` listener rules were deployed.
- Client and admin use the same managed `packages` data. `activePackagesProvider`
  refetches on page entry, account changes and successful admin creation, editing
  or activation changes. Inactive packages are excluded from the client catalog.
- The real package `basic`, created by the user, was confirmed active through
  the same Firestore repository used by the API. No demonstration packages were seeded.

## Local testing without changing deployment defaults

```powershell
npm --prefix functions run build
node functions/scripts/start-live-local.cjs
```

In another terminal:

```powershell
D:\Android\Sdk\platform-tools\adb.exe -s 0874637289000589 reverse tcp:3300 tcp:3300
D:\flutter\bin\flutter.bat run -d 0874637289000589 --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:3300/
```

The local runner uses the operator's existing Firebase CLI login and a temporary
server credential file, removed on normal exit. It reads real cloud Firestore,
not emulators. With no local Brevo key, OTP requests use the configured Render
service. The existing process on port 3000 was preserved.

Development now selects localhost automatically when available; the explicit
override above also remains supported. See [team backend selection](backend-selection.md)
for current setup. Deploy the matching backend changes before using the new
consent and email flows on Render.

For Brevo OTP, Render needs `SIGNUP_EMAIL_OTP_ENABLED=true`, `BREVO_API_KEY`,
`BREVO_SENDER_EMAIL`, and a stable `SIGNUP_OTP_HASH_SECRET` of at least 32 characters.
`BREVO_SENDER_NAME` is optional. Firebase server credentials remain on Render.
The app's direct password recovery needs no additional Render variable.

## Legal links

- `/terms-and-conditions`, with anchors `#account`, `#wellness`, `#packages`,
  `#conduct`, `#privacy`.
- `/privacy-policy`, with anchors `#account`, `#records`, `#photos`, `#choices`.

Both policies use numbered sections and bullet points. Links are public and
remain available before email verification.

The requested unused-page and navigation inventory is in
[app-navigation-audit.md](app-navigation-audit.md).

## Repository state

The task began on `prajwol` with an in-progress merge, eight unmerged index
entries and substantial existing staged and unstaged contributions. Those
contributions were preserved. After validation, the user requested a commit
to `prajwol`, completing the pending merge with these fixes. No branch switch,
reset or push was performed.

## Validation

- The full Flutter suite passed 168 tests, including the repeated-startup
  regression and catalog refresh after admin creation, editing and deactivation.
- Backend unit/type checks cover role authority, consent deferral, package
  operations and password recovery. Emulator-only suites require their separate runtime.
- Device testing used `flutter run` on the connected Infinix with real Firebase.
  The user confirmed login for both roles and client visibility of the admin-created package.
- Live password-reset mailbox delivery was not repeated in this task; the
  restored Firebase SDK path and reset-form behavior were checked by regression tests.
