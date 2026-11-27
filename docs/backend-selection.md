# Local and Render backend selection

Development runs try `http://127.0.0.1:3300/healthz` first. If the local server is
ready, the app uses it. Otherwise it uses `https://fitnep-api.onrender.com/`.
API operations, account checks, OTP requests and hosted session operations all
share the same `BackendResolver`.

Health decisions are cached for 15 seconds. The app checks local availability
again after that interval when the next request arrives. A connection failure
marks that endpoint unavailable for the same interval. Safe GET/HEAD requests
can retry once on the other backend; writes are not automatically replayed.
Authorization failures do not trigger fallback.

Release builds use the configured remote URL and do not automatically probe
localhost. Explicit Firebase emulator mode keeps its existing local-only setup.
Both live backends must use the same Firebase project and Firestore database,
and run the matching authentication/session implementation.

## Team setup

Use Node 22 and sign in with the Firebase CLI for the shared project. Add the
mail settings described in [signup email setup](signup-email-fixes.md) to the
ignored `functions/.secret.local`. Both servers need the same
`SIGNUP_OTP_HASH_SECRET` for password setup and replacement across backends.

```powershell
npm --prefix functions run build
node functions/scripts/start-live-local.cjs
```

Launch a development app normally; an `API_BASE_URL` override is no longer
required to choose localhost automatically.

For an Android emulator, use its laptop address:

```powershell
flutter run --dart-define=LOCAL_API_BASE_URL=http://10.0.2.2:3300/
```

For a physical Android device when device testing is requested, forward port
3300 over USB or set `LOCAL_API_BASE_URL` to the laptop's reachable LAN address.
The local server currently binds loopback, so USB forwarding is the standard path.

Force remote-only testing:

```powershell
flutter run --dart-define=AUTO_LOCAL_BACKEND=false
```

`API_BASE_URL` can still override the primary backend. Development candidates
are the configured local URL, the primary URL, then the existing Render URL.
The local runner reads `.env.local` followed by the ignored `.secret.local`,
which overrides blank template values.

The current task's testing after the laptop-only request did not use the phone.
See [email delivery evidence](signup-email-fixes.md) for confirmed OTP and
temporary-password delivery, and the environment values to copy to Render.
