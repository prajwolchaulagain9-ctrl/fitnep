# Prajwol — Sprint 2 Day 2 handoff

Date: 23 November 2026, Asia/Kathmandu. Stories: US 6 and the US 73 health-read
boundary. Working branch: `prajwol`; implementation began from published
`b7e6f2981bda6793d8ee0c7ff742c8b5f3958edc`. Barsha remains integration/release
owner. The application's scope is Android/iOS.

## Implemented

- One current-assignment/consent guard serves nutrition, activity, meal-photo
  and progress-photo reads. The owner keeps access to saved records. Dietitians
  must match `dietitian_id`; staff/admin must appear in `team_member_ids` on the
  same active `client_assignments/{clientUid}` document. Role or audit permission
  alone grants no clinical access. Missing, inactive or malformed teams deny it.
- List, detail and binary-photo reads use `AuditedHealthReadService`. Assignment,
  current policy, sharing choices, record reads and the successful audit append
  share a Firestore transaction. The HTTP response waits for that commit. Audit
  failure returns no health content.
- Lists audit exactly the returned page's IDs, up to 50. Detail/photo events
  identify the exact client/category/record. Denied authorized attempts record
  the same protected target. Audit metadata omits health answers, photo bytes,
  Firebase tokens and platform session IDs.
- Photos remain private Firestore bytes, served through authenticated endpoints
  with `Cache-Control: no-store` and `X-Content-Type-Options: nosniff`. Record
  projections omit public/download URL fields, including unexpected stored
  metadata. Direct Firestore reads remain denied to application accounts.
- The existing shared policy guard also provides typed access contracts for
  later diet-plan, weight, message and intake readers, including owner-only
  drafts. Their tests are contract fixtures; their business workflows and UI
  are not delivered by this change.
- App-wide policy copy/version and image paths live in `lib/core/constants`.
  Existing wordmark, Google button and privacy-option widgets are reused.
- The shared router starts at the welcome boundary, then routes authenticated
  users by their current role. This closes the pre-existing admin-page startup
  shortcut exposed by the full widget regression run.

## API and consumer contract

`/clients/:clientId/records/:category` supports GET with an optional `after`
cursor, and the existing POST collection boundary. New GET
`/:recordId` returns one projected record; GET `/:recordId/photo` returns private
image bytes. All use the same authorization/audit path. Hosted requests still
require the Firebase ID token and `X-FitNEP-Session` from the Day 1 contract.

`currentAssignedTeam` preserves the existing `dietitian_id` field and accepts
optional server-managed `team_member_ids`. An absent support list grants no
support-member access. Historical assignments never grant access. The reader
does not create assignments or change workload/history; Dilochan owns that
producer and eligibility validation.

Future producers must derive client ownership, record identity/version and
visibility from trusted stored data and enforce their resource-specific rules
inside the audited read callback. They must not use request-supplied owner IDs
or serve a persisted private cache after a denial, logout or account switch.

## Updated policy and rollout

Policy version **2** describes the explicitly assigned FitNEP team. Version 1
described dietitian access; it is not treated as renewed team consent. Internal
reads require the target client's current saved acceptance and category sharing.
The existing registration/privacy gate requests acceptance of version 2,
including guardian confirmation when required. The backend session gate and
Firestore sharing/acceptance rules require the same version.

Deploy the reviewed API, updated Firestore rules and app build together before
online acceptance. Older app builds cannot submit version 2 consent. The live
Day 1 evidence does not validate this new implementation.

## Verification

All local checks passed with Node 22.23.5 and the established Java/Flutter
runtimes. [Verification evidence](sprint2-day2-verification.json) records the
commands, results and hashes of the verified source/test/config files.

| Check | Result |
| --- | --- |
| Backend build | Passed |
| Backend unit/API regression | 66 passed, 0 failed |
| Full Auth/Functions/Firestore emulator regression | 79 passed, 0 failed, 0 skipped |
| Flutter analyze | No issues found |
| Flutter test | 141 passed, 0 failed |

With Node 22 and a supported Java runtime:

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = '60'
npm --prefix functions run build
npm --prefix functions test
firebase emulators:exec --config firebase.json --only auth,functions,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:emulator"
flutter analyze
flutter test
```

The Windows emulator run needs the longer discovery window for cold Firebase
SDK initialization. The default 10-second discovery window failed to register
Functions during one run; that run is not counted as passing regression proof.

The new negative checks cover two clients, assigned/unassigned internal roles,
inactive/reassigned teams, sharing withdrawal, stale role contexts, version 1
consent, direct SDK/public photo access, URL-field projection, audit rollback,
pagination and future resource access contracts. Emulator data is synthetic.

## Remaining integration evidence

- [ ] Producer/consumer acknowledgment of the team and policy version contract.
- [ ] Reviewed API/rules deployment with an identified backend SHA.
- [ ] Barsha's native platform-session integration and the configured hosted URL.
- [ ] Two-client and assigned/unassigned-role checks against that hosted build,
      followed by actual Android/iOS device evidence.

Local implementation/test evidence does not close the Day 2 online/device exit
gate, later business-producer integration or the final main-release checklist.
