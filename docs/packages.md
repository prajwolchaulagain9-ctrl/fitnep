# US 9 package selection

The client route is `/client/packages`, linked from About FitNEP and client home.
It uses the shared theme, Firebase session, and authenticated API client.

## Current delivery and integration limits

The catalog, confirmation, Pending membership, Active dates/days remaining,
Scheduled and Expired states, retry, and account cleanup are implemented.
Server operations are persisted and tested with Firebase Auth/Firestore emulators.
Functions and rules have not been deployed. Spark billing is unchanged.

US 9 is not yet live acceptance complete. The US 1 owner must connect login and
first-login navigation with trusted `role: client` claims. The US 68 owner must
agree the catalog schema and populate real packages. The team must agree a live
hosting arrangement for the API and trusted verified-payment processing.
No placeholder catalog is displayed in the production app.

## API and ownership

`API_BASE_URL` uses the same service as notifications.
Every endpoint verifies Firebase ID tokens with revocation checking.
Membership operations require the verified client role. UID comes from the
verified token; clients cannot supply an owner, status, price, or activation dates.

| Endpoint | Response/request |
| --- | --- |
| `GET /packages` | `data.packages`: active catalog items |
| `GET /memberships/me` | `data.memberships`: only this client's records |
| `POST /memberships` | `{ "package_id": "basic", "request_id": "unique-request-id-01" }`; returns `data.membership` |

Catalog fields are `id`, `name`, `duration_days`, integer `price_npr`, and
`features` (nonempty string array). Catalog documents live in
`package_catalog/{id}` and additionally have Boolean `active`.
Prices are whole Nepalese rupees for this sprint; fractional pricing needs an
explicit contract change. Invalid active catalog entries fail closed.

## Persistence and lifecycle

`package_memberships/{id}` stores `client_id`, the entire selected `package`
snapshot, `status`, and ISO UTC `created_at`. The ID is a hash of the authenticated
UID and request ID. Retrying a request returns its original record. Concurrent
requests for the same package return the client's existing Pending membership.
Only one Pending selection is allowed at a time; changing or cancelling a saved
selection is a future operation, not an activation shortcut.

Catalog activation is rechecked inside the selection transaction. Changes to
catalog prices/features do not alter an existing membership's snapshot.
Membership and guard collections remain inaccessible to direct client writes
and reads. The API is the only client data path.

`onPackagePaymentVerified` reacts to writes in `payments/{paymentId}`.
Trusted payment processing must persist all of these fields:

```json
{
  "membership_id": "<selected membership ID>",
  "recipient_id": "<client UID>",
  "amount_npr": 2500,
  "currency": "NPR",
  "status": "paid",
  "verified": true
}
```

`confirmed` and `succeeded` are also accepted successful statuses. The verified
flag is produced by trusted payment processing, never by the mobile app. Amount,
currency, owner and membership must match the saved snapshot. No client-facing
activation endpoint exists. Replayed events for the same payment are harmless.
Transient transaction failures retry; invalid payment/membership events are
logged for the payment owner to resolve.

Activation sets `start_at`, `end_at`, and `payment_id`. The default start is the
verification time; trusted processing may supply a future ISO UTC
`membership_start_at`. A day is 24 hours. Membership intervals include the start
and exclude the end: `[start_at, end_at)`. Adjacent intervals are allowed.
Every selection/activation transaction touches
`package_membership_guards/{uid}`. Concurrent activations are serialized and
recheck all that client's active intervals before committing. Malformed existing
dates block activation. Other backend writers must use this operation rather
than bypassing its guard with direct Admin SDK mutations.

The API reports `pending`, `scheduled`, `active`, or `expired`, plus server-derived
`days_remaining`. Flutter displays dates in Nepal time (UTC+05:45). Remaining
days round up during an Active interval and become zero at its end.

## Checks

Package security tests run with Auth and Firestore only, to isolate transaction
checks from asynchronous workflow execution:

```powershell
firebase emulators:exec --only auth,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:packages:emulator"
flutter test test/features/packages/packages_page_test.dart
```

The full backend emulator suite also checks the real verified-payment trigger.
Build the backend first and set `FITNEP_RUN_TRIGGER_TESTS=true`:

```powershell
npm --prefix functions run build
firebase emulators:exec --only auth,functions,firestore --project demo-fitnep --non-interactive "npm --prefix functions run test:emulator"
```

Local tests cover required catalog fields, stale/deactivated selections,
idempotency, Pending snapshot persistence, ownership, denied client activation,
direct Firestore denial, verified/mismatched payments, concurrent overlap,
adjacent dates, exact expiry, revoked sessions, compact UI, and retry/account
changes. Emulator fixture package prices are test data, not live product offers.

The completed local check set passed 76 Flutter tests, 18 backend unit tests,
22 integrated emulator checks and eight package transaction/security checks,
plus formatting and analysis. The final payment-trigger filter was rechecked
separately. Local backend execution used Node 24; CI and the declared runtime
use Node 22. These results do not certify live catalog or payment integration.
