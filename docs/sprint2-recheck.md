# Sprint 2 recheck

## Android debug build

The debug APK built for this recheck connects to the local API at port 3300.
The local API uses the shared Firebase project and private Cloudinary storage.
Start it from the repository with Node 22 and the Firebase CLI signed into that project.
The local Cloudinary connection uses `CLOUDINARY_URL` in the ignored
`functions/.secret.local` file.

```powershell
npm --prefix functions run build
node functions/scripts/start-live-local.cjs
```

With a USB-debugging device connected, forward the API port and install the APK.

```powershell
& 'D:\Android\SDK\platform-tools\adb.exe' reverse tcp:3300 tcp:3300
& 'D:\Android\SDK\platform-tools\adb.exe' install -r build/app/outputs/flutter-apk/app-debug.apk
```

## Acceptance evidence

| Sprint story | Implementation and local checks |
| --- | --- |
| US 6 | Firebase Auth and Firestore emulator tests cover cross-client access, team assignment changes, consent withdrawal, and the audit write required before protected reads return. Weight history is derived from submitted intake versions. The Cloudinary smoke test verified private upload and authenticated download. |
| US 10 | Flutter tests cover the QR screen, required image selection, upload retry, and payment history. Firebase tests exercise submission, rejection reasons, replay, and duplicate proof. The server supplies the selected amount, QR method, and a unique checkout reference. This replaces the planned manual entry. |
| US 11 | Firebase tests cover the verification queue, staff grants and revocation, protected receipt access, rejection and its reason, atomic membership activation or scheduling, one notification per decision, and immutable adjustments. Flutter tests cover proof preview and reviewer confirmation. |
| US 12 | Registration tests cover email and Google sign-in, privacy consent, onboarding and deep-link gating. Onboarding captures height and weight for BMI and saves progress when skipped. The separate intake retains profile, health, nutrition, and preference questions with draft and version history. Existing additional measurements remain readable in historical records. |
| US 14 | Firebase checks exercise active membership eligibility, workload counts, assignment and reassignment notices, assignment audit history, and denial for the former dietitian. |
| US 15 | Firebase and Flutter tests cover the scoped client directory, package and plan status, last activity, name and status filters across pages, and the empty state. |
| US 16 | The tests open the assigned client's submitted intake with allergies and conditions first, enforce the current version when reviewing, and record and notify requests for more information. |
| US 73 | The audit suite covers actor, target, time, filters, append-only rules, and admin or explicitly granted staff access. The real diet-plan workflow records creation, submission, return, revision, approval, and publication. A draft revision leaves the previous published version visible to the client. |

The QR is a placeholder and cannot receive a bank payment. The app checks
duplicate checkout references and identical proof images. It has no bank
transaction reference to compare across different screenshots. When a client
has time left on a paid membership, a verified new selection starts at the
previous term's end.

Public Render rollout, an independent device journey, native photo picking,
iOS validation, and release promotion are unverified.

## API-to-page check

Flutter rendered responses from the local HTTP API using Firebase Auth and
Firestore emulators. The check followed consent and onboarding, package
selection, proof upload and review, membership dates, payment notifications,
admin assignment and audit filters, privacy preferences, and the dietitian
intake review. The client opened the dietitian’s saved clarification from
their notification. The test supplied a synthetic PNG in place of the
native gallery picker.

The check found that the admin client profile was reading legacy package
and payment fields, and the staff repository omitted the hosted session
header. The admin profile now shows the stored membership and payment
history, and the dietitian picker loads staff records through the same
local backend and session as the assignment API.

The updated build was installed on the Infinix X6817 with `flutter run`
through USB forwarding to port 3300. The native app rendered the package
catalogue and staff records from the local API backed by shared Firebase.
