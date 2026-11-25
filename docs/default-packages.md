# Default live packages

Configured in the existing `fitnep-88908` Firestore project on 25 November 2026.
The app and existing Render API use the managed `packages` collection.

| Package | Duration | Total price (NPR) | Included guidance |
| --- | --- | --- | --- |
| Basic | 1 calendar month | 2,500 | Personalized nutrition guidance, weekly check-ins, healthy meal planning tips |
| Standard | 2 calendar months | 4,500 | Personalized nutrition and activity guidance, progress reviews, care team support |
| Premium | 3 calendar months | 8,000 | Personalized nutrition and fitness coaching, weekly progress reviews, priority care team support |

The two inspected temporary Basic/Premium documents were updated using the
existing package service, keeping their IDs and original creation metadata.
Standard was created as `fitnep-default-standard-v1`. Package change history
records the actual signed-in administrator and the before/after values.

Both existing Pending memberships were compared before and after the update;
their complete persisted contents remained unchanged. Their saved old terms
remain valid snapshots until their normal payment/membership workflow resolves
them. No membership, payment, assignment or historic package entry was deleted.

`functions/scripts/configure-default-packages.cjs` previews changes by default.
An explicit `--apply` enables writes. It uses the operator's existing Firebase
CLI login, requires an active app administrator, refuses emulators and refuses
to overwrite package values that differ from the inspected temporary values or
these defaults. It does not run automatically during app/server startup.

Run from the repository root after compiling the backend:

```powershell
node functions/scripts/configure-default-packages.cjs
node functions/scripts/configure-default-packages.cjs --apply
```

The pre-change catalogue backup is retained in the ignored
`.dart_tool/default-packages` directory. Independent Firestore inspection
confirmed all three packages active, with the configured prices, durations and
feature lists. Existing package service regression coverage was retained;
the live setup also asserts every saved default and unchanged memberships.
