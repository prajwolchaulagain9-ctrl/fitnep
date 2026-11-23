# Standalone hosted API setup

The Sprint 2 backend runs the existing Express API on Node 22 with cloud
Firebase Auth and Firestore. The standalone entry point is
functions/src/server.ts; npm start runs its compiled output. A Firebase
Functions deployment is not needed for this runner.

The API is deployed at https://fitnep-api.onrender.com. Eight live
health/session/audit checks passed on 22 November 2026; see the
[verification evidence](sprint2-day1-live-verification.json).
The current Flutter client still needs the session/auth integration listed in
[the Day 1 handoff](sprint2-day1.md). The steps below describe the service setup.

## Create the Render service

1. Have the feature change reviewed and merged into development. The
   [render.yaml](../render.yaml) Blueprint deliberately uses that branch.
2. In the Render Dashboard, create a Blueprint from
   https://github.com/prajwolchaulagain9-ctrl/fitnep-, using development and
   the root render.yaml.
3. Supply these private environment values when prompted:

   | Variable | Value |
   | --- | --- |
   | FIREBASE_PROJECT_ID | The owned Firebase project, currently fitnep-88908 |
   | FIREBASE_SERVICE_ACCOUNT_JSON | The complete JSON credential for that project's dedicated backend service account |

   Keep the service-account JSON in the host's secret environment. The runtime
   needs Firebase Auth account-read permissions and Firestore data access.
   Do not put the credential in Flutter, Git, evidence files or chat.
4. Deploy the reviewed commit manually. The Blueprint selects Node 22,
   Singapore, the Free plan, functions as the root directory,
   npm ci --include=dev && npm run build, and npm start. Automatic deploys
   are disabled while the candidate is being reviewed.
5. Publish the reviewed Firestore rules/indexes to the same project through the
   team's deployment account:

   ~~~powershell
   firebase deploy --only firestore:rules,firestore:indexes --project fitnep-88908
   ~~~

6. Open the actual provider-assigned HTTPS URL at /healthz. Expect HTTP 200:

   ~~~json
   {
     "data": {
       "ready": true,
       "build_sha": "the actual full deployed commit SHA",
       "node_version": "v22.x.x"
     }
   }
   ~~~

   RENDER_GIT_COMMIT supplies the build SHA. Readiness checks cloud Firestore;
   an unknown build or unavailable database cannot return a healthy response.
   Record the real URL/SHA, then verify persistence after service restart.

The runner refuses emulator environment variables, the demo-fitnep project,
unknown commit SHAs, wrong-project JSON credentials and invalid port/timeout
settings. It binds to Render's PORT on 0.0.0.0.

For a different Node host, set FITNEP_BUILD_SHA to the deployed full SHA.
GOOGLE_APPLICATION_CREDENTIALS can point to a private server-side credential
file instead of using the JSON environment variable. Local Node 22 can load an
ignored .env with node --env-file=.env lib/server.js after building.

## Session contract

Every hosted business request carries both:

- Authorization: Bearer FIREBASE_ID_TOKEN
- X-FitNEP-Session: PLATFORM_SESSION_ID

| Endpoint | Required input | Result |
| --- | --- | --- |
| POST /sessions/start | Firebase token; empty body | Existing valid session or a new opaque session plus identity/expiry/permissions |
| GET /sessions/me | Both headers | Current identity/expiry/permissions; does not extend expiry |
| POST /sessions/activity | Both headers; empty body | Extends expiry for reported human activity, at most once per minute |
| POST /sessions/end | Both headers; empty body | HTTP 204; closes that authentication context and appends one logout event |

Persist the opaque ID in secure client storage. The session_id returned by
start must stay out of logs. The unrelated server-created X-Request-Id is the
non-secret audit correlation ID.

The verifier checks Firebase revocation and reads the current Firebase Auth
account on every request. Current custom claims supply role, role_version,
must_change_password and permissions.audit_read/payments_verify. Legacy
role versions default to zero; verified accounts without a role remain clients.
A token's old privileged claims cannot override current account state.

The session guard checks owner UID, authentication time, current role/version/
permissions, revocation, expiry, required password change, the current saved
privacy acceptance for clients, and any server-owned login lock. The default
idle timeout is 900 seconds. Polling, repeated start and process restart do not
renew it. Expired or logged-out contexts require reauthentication.

Firebase auth_time has second precision. A new sign-in during the same
second as a closed context can be refused until a later authentication time.
The client must reauthenticate rather than retrying the captured token.

## Integration still required

Barsha connects native session start/storage/activity/end, credential exchange,
the configurable failed-login producer, hosted signup/OTP/recovery adapters,
offline logout reconciliation and cache cleanup. Tanmay connects saved
acceptance/DOB/guardian onboarding and account/permission mutations. The guard
consumes platform_login_state/{uid}.locked_until as a Firestore Timestamp;
the actual failed-attempt/lockout writer remains Day 2 work.

The hosted runner disables /admin/memberships/:id/verify-payment, which
manufactures a demonstration payment. The real submission/verification flows
remain Barsha's US 10/11 work.

Standalone Node does not execute undeployed Firestore Functions triggers.
Day 1 provides the transaction/outbox writer contract; the delivery/recovery
worker and actual business-event producers are Day 3 integrations. The
[Day 2 implementation](sprint2-day2.md) adds assigned-team/audited health reads
and policy version 2. Its deployment and online acceptance are pending; the
recorded live Day 1 build does not establish those new behaviors.

Render Free sleeps after inactivity. Barsha must connect the planned bounded
cold-start retry/loading behavior before phone acceptance. Confirm current free
account eligibility and quotas when creating the service.

References: [Blueprint specification](https://render.com/docs/blueprint-spec),
[Node version selection](https://render.com/docs/node-version),
[Free service behavior](https://render.com/docs/free).
