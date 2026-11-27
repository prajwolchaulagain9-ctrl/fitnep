# FitNEP Sprint 2 Day 6 local acceptance

The review ran on `prajwol` on 26 November 2026 (Nepal time), starting at `9c31ec5`. Its ancestry includes the local tracking refs for all teammate branches, including Dilochan’s `c56cc3a` and Tanmay’s `a4c811c`. Local `main` and its tracking ref are at `6e646ac`. Hosted acceptance and signed-candidate review remain open.

## Test runs

| Check | Result |
| --- | --- |
| `flutter analyze --no-pub` | Clean |
| `flutter test --no-pub -r expanded` | 191 passed, including the merged theme, package and intake widgets |
| `npm --prefix functions run build` and `npm --prefix functions test` | Build and type check passed. 116 backend unit and API tests passed. |
| Firebase Auth, Firestore and Functions emulators with `FITNEP_RUN_TRIGGER_TESTS=true` and `npm --prefix functions run test:emulator` | 157 passed |
| Firebase Auth and Firestore emulators with `npm --prefix functions run test:packages:emulator` | 11 passed, including both overlap cases |

The emulators used `demo-fitnep`, synthetic accounts and Node 24.11.1. The first package run shared the Functions emulator, whose payment trigger competed with the suite’s explicit activation. The package checks passed with the CI configuration, which runs that suite with Auth and Firestore only.

## Prajwol acceptance

| Criterion | Local evidence and remaining work |
| --- | --- |
| US73-AC1 | Session start, role changes, assignment, intake review and health reads persisted events in the emulator. Shared payment decisions and intake submission/revision still need their business producers. |
| US73-AC2 | The audit API and Flutter page show the actor, action, target and server time. The Firebase suite verifies that app identities cannot write to the audit store. The new list projects approved metadata fields. |
| US73-AC3 | The emulator retained all six plan events with actor, timestamp and version on trusted fixtures. The plan timeline opens from the audit list. The plan workflow still needs to emit those events. |
| US73-AC4 | The audit endpoint combined actor, action, client, dietitian, status and Nepal date filters across three pages, including equal timestamps and an empty intermediate page. The widget test verified that filter values persist when loading the next page. |
| US73-AC5 | Admin and explicitly granted staff received metadata. Ordinary staff, a dietitian and a client were denied. A grant change invalidated the previous hosted session in the emulator and removed the open audit page in Flutter on revocation. The grant conferred neither payment approval nor unassigned health access. |
| US6-AC1 | Client isolation was verified with two synthetic clients and the implemented record readers. Later plan, message and weight contracts used fixture records. |
| US6-AC2 | The Firebase suite covered assigned and unassigned staff, dietitian and admin actors. Reassignment removed the former dietitian’s access on their next request. |
| US6-AC3 | List, detail and photo reads committed trusted metadata before returning data. A simulated audit failure withheld the data. |
| US6-AC4 | The Firebase suite denied unauthorized and direct photo access and checked that the private-photo response omitted public URLs. |
| US2-AC1 | Flutter exercised the recovery entry and the backend checked request behavior. Receipt and use of a real email remain open for the signed candidate. |
| US2-AC2 | Local tests cover code verification, expiration errors and single-use behavior. Expiry at the configured live provider remains open here. |
| US2-AC3 | Local API and widget checks cover equivalent confirmation for registered and unknown addresses. |
| US2-AC4 | Local API and widget checks cover rejection of weak passwords. |
| US2-AC5 | Local emulator and Flutter checks cover invalidation of existing sessions and sign-in with the new password. |
| US9-AC1 | The package emulator returned active catalogue terms. Flutter rendered the shared package cards. |
| US9-AC2 | Concurrent selections produced one durable Pending snapshot. Client identity, price and activation overrides were rejected. |
| US9-AC3 | A verified emulator payment activated the membership with dates and days remaining. Flutter rendered the resulting membership shape. |
| US9-AC4 | Deactivation hid the package and stale selection was rejected. |
| US9-AC5 | The package emulator admitted one competing activation and accepted adjacent intervals. |

## Dilochan acceptance

| Criterion | Local evidence and remaining work |
| --- | --- |
| US14-AC1 | The assignment API and widgets covered Active eligibility and rejected Pending, expired and other ineligible states. |
| US14-AC2 | Availability and workload counts came from the API. The assignment widget displayed current counts. |
| US14-AC3 | The assigned dietitian could open the client. The worker delivered the assignment and available-intake notices to that dietitian once. |
| US14-AC4 | The Firebase suite retained the old assignment history, switched intake access to the replacement and denied the previous assignee. |
| US14-AC5 | The assignment and reassignment audit checks verified the actor, client, previous and new assignee, version and timestamp. |
| US16-AC1 | The assigned dietitian opened the full intake in Flutter with allergies and medical conditions above the answers. The compact-width regression test covers the heading that previously overflowed. |
| US16-AC2 | Reviewed, missing information and clarification persisted. An explicitly stale version was rejected. The API also accepted a review with the version omitted, even on intake version 2. |
| US16-AC3 | The request persisted as Pending Information. The worker sent a generic notice and the Flutter notification opened the protected intake with its note. A request still queued when the intake was marked Reviewed also sent, even though its request had been superseded. |
| US16-AC4 | The API denied another dietitian and the previous assignee. |
| US68-AC1 | The authenticated admin could create a package with its required terms. |
| US68-AC2 | Edit and deactivation updated the catalogue and non-admin mutations were denied. |
| US68-AC3 | Existing purchase snapshots kept their original terms after a catalogue edit. |
| US68-AC4 | Package history recorded the actor and timestamp. The package producer still needs entries in the shared audit trail. |
| US64-AC1 | Widget and Firebase tests covered newest-first order and read/unread state. |
| US64-AC2 | Flutter exercised the supported record destinations and the client intake request. Rejected payment notices and later producers still need end-to-end evidence. |
| US64-AC3 | Mark-all-as-read changed only the authenticated recipient’s state and persisted locally. |
| US64-AC4 | The suite denied cross-recipient list, detail and mark-as-read access, including administrator access to other recipients’ notifications. |

## Handoff

- Dilochan owns the two intake-review gaps. In the local probe, `day6-probe-dietitian` requested missing information on version 2 of `day6-probe-client` and then marked that version Reviewed without sending an expected version. Draining the worker delivered one “Intake information requested” notice while the saved form was already Reviewed.
- Tanmay’s client intake flow still needs a way to respond and resubmit from the read-only request screen. Submission and revision also need the shared audit and notification events described in the Day 3–4 handoff.
- Barsha’s full payment submission, verification and rejection flow still needs to write its decision and activation events. Local tests cover the existing manual activation and notification contracts.
- The audit reader uses the new `audit_events` indexes in the repository. Hosted acceptance requires deployment of those indexes and a matching app/backend build. The audit-read grant is available through the existing admin account API.

Related evidence is in the [Day 2 privacy handoff](sprint2-day2.md), [Day 3–4 producer handoff](sprint2-day3-day4.md) and [audit and RBAC emulator tests](../functions/test/rbac_emulator.test.ts).

## Tanmay’s US12 and US15 follow-up

Local verification ran against the US12 and US15 changes based on `033aad6`. The Firebase Auth, Firestore and Functions emulators used project `demo-fitnep` with synthetic accounts `client`, `other-client`, `dietitian` and `replacement`. The signed app and deployed backend still need joint acceptance.

| Criterion | Local evidence |
| --- | --- |
| US12-AC1 | My profile collects name, date of birth and contact details. The health intake collects height and weight, optional waist, hip and chest measurements, goals, medical history, allergies, restrictions and food preferences. BMI is derived from the measurements. |
| US12-AC2 | The Flutter editor blocks a submission with blank allergies while allowing a partial draft. Backend tests cover explicit None, numeric bounds and guardian confirmation. |
| US12-AC3 | The editor test closes and reopens the form and restores the saved age and name with guardian confirmation. The emulator restores the saved owner draft and keeps it private from the assigned dietitian. |
| US12-AC4 | The emulator confirms one intake notice per version for the current dietitian, including submission before assignment. Clients can open a pending request and resubmit. The original versions stay readable to the assigned team. The worker checks the current version, review revision and reviewer before sending a queued request. |
| US12-AC5 | The emulator verifies owner and assigned-team access and denies unrelated clients and former assignees. Consent withdrawal, account deactivation and stale roles remove access. |
| US15-AC1 | The list shows client name, package status, actual plan status and last activity. New client-visible plans have a Published status. The emulator distinguishes a missing plan from one with unavailable status and verifies that an invalid legacy purchase leaves the assigned client in the list. |
| US15-AC2 | The emulator exercises name and plan filters across pages. The Flutter widget tests preserve the filters while requesting further results. |
| US15-AC3 | The server scopes the list to the signed-in dietitian and removes reassigned clients on the next load. The widget refreshes the directory on resume and after closing a client profile. |
| US15-AC4 | An empty directory shows “No active clients are assigned to you.” A search with zero matches has a separate message. |

The backend keeps the current intake in `client_intakes/{uid}`, the owner draft in `private/draft` and immutable snapshots in `versions/{version}` under that intake. Reviews live in `intake_review_history`. The notification worker uses the operation ID already stored in the outbox to identify the current review, so pending events created by earlier builds remain readable. The existing repository preserves the previous submitted snapshot when a legacy intake is first revised.

The [intake and directory emulator cases](../functions/test/day34_recovery_emulator.test.ts) and [route widget tests](../test/widgets/role_authorization_test.dart) cover the local integration. Close signed-candidate acceptance by running the same journey against a matching deployed backend with authorized test accounts and recording the app and backend SHAs in the team’s acceptance tracker.
