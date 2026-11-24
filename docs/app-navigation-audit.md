# Current app pages and unused UI — updated 24 November 2026

This inventory follows the normal live app (`USE_FIREBASE_EMULATORS=false`),
the router registrations, the role navigation drawer and notification destinations.
Unrelated work has been retained.

## Not used in the normal app

| File or UI | Current status |
| --- | --- |
| `lib/features/authentication/presentation/pages/app_under_development_page.dart` | `AppUnderDevelopmentPage` has no caller. `/app-under-development` redirects to the appropriate current flow instead. |
| `lib/features/onboarding/presentation/pages/demo_entry_page.dart` | `/demo` is registered only with Firebase emulator mode enabled. No live-app entry. |
| `lib/features/packages/presentation/pages/packages_page.dart` | Alternate package UI used only by the emulator route. Live clients use `PackageSelectionPage`. |
| `PrivacyPolicyPage.review` and its private acceptance screen in `privacy_policy_page.dart` | Legacy age/guardian review UI has no current caller. Normal signup and consent use explicit agreement and public policy links; the legacy implementation is retained. |
| `lib/features/admin/data/datasources/admin_local_datasource.dart` | Mock admin datasource used by tests only. Production uses `AdminRemoteDatasource`. |

## Public navigation

| Page | Path | How users reach it |
| --- | --- | --- |
| Welcome | `/` | Initial launch and sign-out |
| About | `/about` | Learn about FitNEP |
| Login | `/login` | Welcome, signup, expired session |
| Signup | `/signup` | Welcome and login |
| Forgot password | `/forgot-password` | Login |
| Reset password | `/reset-password` | Recovery confirmation or supported reset deep link |
| Terms and Conditions | `/terms-and-conditions` | Shared legal links |
| Privacy Policy | `/privacy-policy` | Shared legal links and privacy screens |

Email verification (`/verify-email`) and temporary password change
(`/change-staff-password`, shared by staff and Google-created accounts) are
account-dependent steps, not unused pages. Expired Google password recovery
uses `/change-staff-password?recover=google` after a recent Google sign-in.
The consent screen is mounted by `RegistrationPrivacyGate` when required;
it deliberately has no independent route.

## Client navigation

| Page | Path | Entry |
| --- | --- | --- |
| Package selection | `/client/packages` | Client login/signup and drawer |
| Temporary client dashboard | `/client/home` | Saved package selection, empty-catalog continue action, drawer |
| Membership | `/client/membership` | Dashboard and drawer |
| Notifications | `/client/notifications`, `/notifications` | Dashboard bell and drawer |
| Privacy preferences | `/client/privacy-preferences` | Drawer and dashboard |
| Own profile | `/account/profile` | Drawer |
| Own records | `/client/records` | Drawer |

## Admin, staff and dietitian navigation

| Page | Path | Allowed role and entry |
| --- | --- | --- |
| Role dashboard | `/admin/home`, `/staff/home`, `/dietitian/home` | Matching role login and drawer |
| Staff accounts and history | `/admin/staff-accounts`, `/admin/staff-accounts/history` | Admin dashboard/drawer |
| Users and roles | `/admin/users` | Admin dashboard/drawer |
| Client list and profile | `/admin/clients`, `/admin/clients/:id` | Admin dashboard/drawer, then selected client |
| Audit log | `/admin/audit-log` | Admin dashboard/drawer |
| Package management | `/admin/packages` | Admin dashboard/drawer |
| Create package | `/admin/packages/create` | Create package action |
| Edit package | `/admin/packages/:packageId/edit` | Selected package. A direct link without the selected object returns an instruction to use the list. |
| Package history | `/admin/packages/history` | Package management and drawer |
| Payment approvals | `/admin/package-approvals` | Admin dashboard/drawer. Manual verification is disabled in the hosted runner until enabled through the existing workflow. |
| Assigned clients | `/care/clients` | Staff/dietitian dashboard/drawer |
| Assigned client records | `/care/clients/:id/records` | Assigned client selection, with current assignment and privacy authorization |

## Requires real records or notifications

`/diet-plans/:id`, `/messages/:id`, `/tasks/:id`, `/payments/:id`, and
`/dietitian/assigned-clients/:id` are reachable through matching notification
types. They need a valid reference and permitted real data. An empty mailbox
does not make their implementation unused. Unknown notification types have no
destination and show the existing explanatory error.

No age/goal onboarding page is wired into the current journey. That process is
deferred at the user's request.
