# Prajwol — Day 3–4 implementation and mobile UI

25 November 2026, Asia/Kathmandu. Based on the owner plan in
`D:\fitnep_plans\PRAJWOL_SPRINT_2_PLAN.md`. Work remains on `development`,
starting at Dilochan's `7c4786f`; his assignment history, notifications, complete
intake display and review actions are preserved. No main promotion, push or
backend deployment was performed. The reviewed implementation is prepared for
the local commit requested after configuring the [default packages](default-packages.md).

## Integrated changes

- Reconciled committed conflict markers in the hosted/Firebase/demo entry
  points, assignment repository/service, package scripts and emulator security
  tests. All entry points reuse the factory containing the intake service.
- Restored the complete working authentication, legal, account and role router,
  keeping Dilochan's protected intake route. Startup returns to welcome.
- Google credential installation can invalidate its first Firebase token.
  Account/password prerequisite requests now wait for sign-in completion and
  the credential refresh; notices appear after setup. Loading never grants
  access, and real failures remain retryable.
- Added original offline vector characters to welcome, authentication,
  agreement, package introduction, dashboard and empty notifications. Controls
  retain touch targets; forms scroll with keyboard/large text.
- Added the official pub.dev [animations](https://pub.dev/packages/animations)
  package, version 3.0.0, for Android shared-axis transitions. Reduced motion
  removes the movement; iOS retains its platform transition builder.
- Added system/light/dark appearance, a persistent local preference, a toggle
  on public authentication pages and an Appearance control in the drawer.
  Existing admin, package, intake and notification surfaces/text use the theme.
  Dark colors come from [Color Hunt's charcoal/amber palette](https://colorhunt.co/palette/222831393e46ffd369eeeeee):
  `#222831`, `#393E46`, `#FFD369`, `#EEEEEE`, with derived surface/outline tones.
  Shared status treatments remain meaningful in both themes. Body text and
  primary controls have at least 4.5:1 contrast in the tested themes.

## Day 3 current-event integration

- Platform login, current account provisioning/profile/role/status changes,
  assignments, intake reviews and sensitive reads append trusted audit metadata.
  Role/status changes create durable Auth reconciliation operations alongside
  the canonical account mutation. Failed Auth synchronization keeps the operation
  requested; retry completes it and appends synchronization evidence. A
  superseded revision cannot restore the prior canonical authority.
- Assignment mutation/history/audit/outbox commit together. The hosted factory
  uses durable notification delivery instead of awaiting a separate notification
  write after the business transaction.
- The hosted worker drains on startup, after API responses and every 30 seconds
  while awake, with a bounded batch, a recoverable lease and bounded retry delay.
  Immutable event envelopes and mutable deliveries are separate. Notification
  records and handler receipts commit together and use deterministic IDs.
- Recipients come from persisted owners/current assignments. Stale assignment
  events cannot notify the former dietitian. Assignment also delivers one notice
  when a submitted intake already exists. Previews contain no health answers.
- Merged intake reads and review responses use the shared current-account,
  assignment/consent and audited-read boundary. Reviews retain private history,
  identify the submitted version, reject stale versions and queue information
  requests atomically. Owners can open a read-only intake from their notification;
  dietitians retain review controls.

## Day 4 producer contracts

`PlanAuditContract` supports created, submitted, returned, approved, published
and revised events. It validates the actor and trusted stored plan/version/
operation/status, appends metadata with server time and deduplicates operation
receipts. It exposes no arbitrary app-facing event writer. The existing typed
plan, weight and message privacy adapters remain the mandatory read boundary.

The six-event evidence is **contract fixtures**, not a delivered plan editor or
historical production trail. Later producers must adopt the transaction/read
contracts before feature release. No unknown historic actions were reconstructed.

## Research applied

- Flutter's official [responsive-layout skill](https://github.com/flutter/agent-plugins/tree/main/skills/flutter-build-responsive-layout)
  and [layout-fix skill](https://github.com/flutter/agent-plugins/tree/main/skills/flutter-fix-layout-issues).
  Source checked by Git at `ff6d472ee66dbed566c4500edee460c94fde0a02`.
  Skills were read from an ignored research checkout; no global installation.
- Existing Frontend Design and Ponytail skills guided compact shared components
  and retention of the app's established branding.
- Pub.dev `flutter_animate` was also checked; the official `animations` package
  covered the requested page transitions without adding another motion library.

## Actual evidence

- Flutter 3.47.5 / Dart 3.13.4: full regression **186 passed**. After the final
  shared style changes, focused sign-in/contrast/motion/intake/dashboard checks:
  **7 passed**.
- Node backend unit/API regression: **111 passed**.
- Auth + Firestore + Functions emulator regression: **146 passed, 0 failed,
  0 skipped**, including restart, transaction rollback, lease recovery,
  duplicate delivery, stale-team denial and all six plan-event fixtures.
- Native Infinix X6817 (`0874637289000589`) ran through `flutter run` against
  Render. Appearance switching and native Google sign-in to the real package
  catalogue were verified. No Flutter exception was logged in that transition.
  Visual captures are in the ignored `.dart_tool/day34-phone` directory.
- Render remained at `c499eb6a8ddbbd3a04b036c74ccf5066f5046e48`. Its OTP endpoint
  returned 200 after the exact environment names were corrected, and the stored
  code record had `status=sent` and Brevo's accepted message ID. This confirms
  provider acceptance; the user confirmed the issue was resolved, while inbox
  receipt was not independently measured by this run. Temporary-password backend tests verify retry and
  existing-password preservation; this run did not replace an existing Google
  account password merely to force another email.

## Deployment and remaining owner handoffs

- Deploy this matched backend/app update before claiming the new intake-owner
  endpoint or durable worker is online. This phone run's existing login/package
  paths use Render; emulator evidence verifies the new backend changes.
- Barsha owns actual payment submission/decision composition. The worker supports
  trusted payment verified/rejected and membership activated envelopes; her
  producer must append them using the shared transactional writer. Full payment
  workflow evidence remains her handoff, not a completed replacement in this change.
- Tanmay's later intake submission/revision producer must emit its typed events;
  Dilochan's current assignment/review consumers are integrated here.
- Actual plan editing/publication/revision remains with later feature owners.
  Day 5 hosted audit filtering/UI and final online/release acceptance remain
  separate checkpoints. A sleeping free instance resumes its durable backlog
  when awake; this is not continuous background delivery.
- Mail configuration is case-sensitive: `BREVO_API_KEY`, `BREVO_SENDER_EMAIL`,
  `SIGNUP_OTP_HASH_SECRET` (at least 32 characters), and
  `SIGNUP_EMAIL_OTP_ENABLED=true`. Secrets stay in Render/ignored local files.
  Future failures distinguish missing key, invalid sender and invalid OTP secret
  without returning credential values.
