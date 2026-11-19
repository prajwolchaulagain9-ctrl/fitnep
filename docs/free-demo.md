# Zero-budget FitNEP demonstration

No payment gateway, real charge, paid hosting, Firebase billing upgrade, or
Functions deployment is used. The client chooses a package; an admin approves
a simulated payment manually; the client then sees Active dates and days remaining.

## Start the local backend

Use the installed Node, Firebase CLI and Java tools. From the repository root:

```powershell
.\scripts\start-free-demo.ps1
```

Keep this terminal running. It starts local Auth/Firestore emulators and the
shared API at `http://127.0.0.1:3000/`. The server refuses non-local emulator
configuration and always uses `demo-fitnep`. It seeds three fictional packages
and client/admin test accounts with trusted role claims. Normal app data and
the live Spark project are not modified.

Demo state exports to `.dart_tool/free-demo-data` when the server stops and
imports next time. To start with fresh in-memory demonstration data:

```powershell
.\scripts\start-free-demo.ps1 -Reset
```

`-Reset` skips importing the local demo export; it does not delete live data.
The new local state replaces the demo export when the server exits normally.

Use Ctrl+C to stop a demo started in your terminal. If Codex started the current
demo as a hidden background process, stop it and save its state with:

```powershell
.\scripts\stop-free-demo.ps1
```

## Run on the connected Android phone

In another terminal, forward the local ports over USB:

```powershell
D:\Android\Sdk\platform-tools\adb.exe reverse tcp:9099 tcp:9099
D:\Android\Sdk\platform-tools\adb.exe reverse tcp:3000 tcp:3000
flutter run -d 0874637289000589 --dart-define=USE_FIREBASE_EMULATORS=true
```

For an Android emulator, add
`--dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2` and use its device ID.
The demo accepts only local host addresses. Debug network settings permit HTTP
to these emulator hosts; release network settings are unchanged.
Automatic Firebase host rewriting is disabled so a physical Android phone keeps
the USB-forwarded `127.0.0.1` address. Android emulators use the explicit
`10.0.2.2` define above.

The demo build uses a separate named Firebase app and directs Firebase SDKs and
the package API to the laptop. The normal build leaves the emulator flag off.
The separate demo entry route and automatic test-account login are absent from
normal navigation. The laptop must be running and reachable for the demo app
to load/save records. This is a local assessment/demo build, not an internet service.

## Demonstrate US 9

1. Choose **Continue as demo client** and select Basic, Standard, or Premium.
2. Confirm selection. The package displays **Pending** and has no Active dates.
3. Go back and choose **Continue as demo admin**.
4. Open **Review payment** and choose **Verify and activate**. The prefilled
   DEMO reference is an audit marker; no real payment takes place.
5. Go back and sign in as the demo client again. The package displays **Active**,
   start/end dates in Nepal time and server-derived days remaining.

The backend enforces roles, token revocation, price snapshots, idempotency and
date overlap. There is no client activation bypass or payment-gateway SDK.
The demo account emails are `demo-client@fitnep.test` and `demo-admin@fitnep.test`;
their emulator-only password is `FitnepDemo123!`.

The original US 9 criterion requires a verified payment, not a gateway. Manual
admin verification satisfies that workflow; the demonstration uses simulated
verification because real money handling is outside the project scope.

## Repeat the phone check

Build the USB demo APK once:

```powershell
flutter build apk --debug --target-platform=android-arm64 --dart-define=USE_FIREBASE_EMULATORS=true
```

Start a fresh local demo with `scripts/start-free-demo.ps1 -Reset`, then run:

```powershell
python -u scripts/check-free-demo.py --apk build/app/outputs/flutter-apk/app-debug.apk
```

The checker installs the APK, restores USB port forwarding, selects Basic,
verifies it through the admin screen and reloads the client's Active membership.
It checks saved dates, 30 days remaining, the Rs. 2,500 price snapshot and a 403
response when the client tries to approve its own payment. Screenshots are saved
to `.dart_tool/free-demo-check/`. Use `--device` for another USB phone.

The checker requires an empty demo membership list and stops early if previous
demo selections remain. Stop the current server before starting with `-Reset`;
an existing Active package correctly prevents a second overlapping activation.
Keep the phone unlocked and FitNEP visible during the check.

## Verified on 19 November 2026

The ARM64 demo APK passed the complete USB journey on the Infinix X6817:
Basic selection persisted as Pending, the admin manually approved it, and a
fresh client sign-in displayed Active with start/end dates and 30 days remaining.
The checker confirmed a 30-day saved interval, the Rs. 2,500 snapshot and a 403
response for client approval attempts. The Pending, approved and Active
screenshots are in `.dart_tool/free-demo-check/`.

Validation also passed 77 Flutter tests, 18 backend unit tests, nine package
Auth/Firestore emulator tests, Dart formatting and the Flutter analyzer.
The package tests cover immutable audit records, concurrent approval retries,
ownership, revoked sessions, expiry and atomic rejection of overlapping dates.
Backend checks used the installed Node 24; the declared/CI runtime is Node 22.

The checked artifact is `build/app/outputs/flutter-apk/fitnep-free-demo.apk`
(SHA-256 `a5dfb2863390a01cb6982f5c3af7e1a1553d033a06b63d4fa5bc7957866c51b0`).
This verifies the local assessment/demo workflow. Live shared hosting, the
normal app's US 1 login handoff and real US 68 catalog remain team dependencies.
