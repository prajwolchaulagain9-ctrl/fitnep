# Signup email delivery — 24 November 2026

## Result

The laptop can send actual signup OTP and Google-account temporary-password
emails through Brevo. The local backend uses real Firebase Auth and Firestore.
No phone operations were performed after the user requested laptop-only tests.

The original mail configuration had three concrete blockers:

- Brevo rejected the laptop's unrecognized IP address. After the user updated
  the account's IP settings, the API accepted requests and confirmed the sender active.
- The supplied OTP hash secret had 31 characters; the existing service requires
  at least 32. A new random 64-character secret was generated in the ignored
  `functions/.secret.local` file.
- The local runner loaded a blank sender from `.env.local` before the secret
  file. It now explicitly merges those files so the secret file overrides the template.

Secrets remain outside Git and Flutter. On Render, copy the current values of
`BREVO_API_KEY`, `SIGNUP_OTP_HASH_SECRET` and `BREVO_SENDER_EMAIL` from the local
secret file; keep `SIGNUP_EMAIL_OTP_ENABLED=true`. `BREVO_SENDER_NAME` is optional.
The sender is `prajwolchaulagain660@gmail.com`.

## Application behavior

- A shared `BrevoMailer` sends OTP and temporary-password emails. It requires
  Brevo's accepted message ID before reporting successful submission.
- OTPs remain six digits, expire after ten minutes, are bound to the verified
  Firebase identity's email, and retain the existing attempt/resend limits.
  Provider failures do not leave a usable code marked as successfully sent.
- `POST /auth/google/email-password` accepts no account identifier or password
  from the client. It requires an enabled, verified account with a recent
  Google sign-in.
- Google-only accounts receive a random temporary password that enables
  email/password login on the same Firebase UID. Existing passwords are preserved.
- Temporary passwords expire after 24 hours and require replacement before
  protected application access on email login. Google sessions continue to
  use their regular flow.
- A pending delivery retains an encrypted password for retry. Delivery retries
  reuse the installed password; they do not keep replacing account credentials.
  Ciphertext, IV and authentication tag are removed after accepted delivery.
- The existing change-password screen and endpoint handle these client
  temporary passwords as well as staff passwords. A recent Google sign-in
  allows choosing a permanent password after expiry. Subsequent Google logins
  preserve installed passwords. Replacement revokes old sessions.
- Flutter re-exchanges the Google credential after installing a password,
  because Firebase invalidates the previous credential session on password installation.

## Laptop evidence

Brevo reported `delivered` for the signup OTP sent to
`prajwolchaulagain9+fitnep-otp-test@gmail.com` and the temporary password sent to
the explicitly selected Google-only account `chaulagainprajwol660@gmail.com`.
The OTP alias reaches the authorized Gmail inbox. Its temporary test account
was removed after delivery verification.

The temporary-password acceptance check used trusted operator setup for the
selected real Google-only account, then the actual Firebase email/password
sign-in API and local application's `/session` endpoint. Login succeeded,
`must_change_password` was true, and `/packages` returned 403 until password
replacement. The emailed password remains available for the user to replace;
the acceptance check did not select a permanent password for them.

The full Flutter regression suite passed 175 checks, including Google recovery
and local/Render selection. The backend suite includes 99 checks.
The public Google-token route, code verification, password replacement,
expiry, retry, existing-password preservation and credential-session refresh
are covered by automated backend and Flutter checks. Native Google OAuth was
not repeated after the user requested laptop-only testing.

## Deployment

The new handlers are installed in the local backend. At the user's request,
the validated changes are committed on `prajwol` together with the previously
pending merge. No push or Render deployment was performed.
Deploy the matching backend source from `development` and copy the mail
configuration before testing this new flow on Render.

Development runs now select a healthy local backend automatically and fall back
to Render; see [team backend setup](backend-selection.md).
