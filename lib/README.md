# Where to find Flutter code

- `app/` starts the app and contains routes and the theme.
- `features/` groups screens and related code by what they do. Open `onboarding/` for client setup, `packages/` for packages and membership, or `admin/` for the admin workspace.
- Inside a feature, `pages/` contains screens, `data/` contains API calls and models, and `widgets/` contains widgets specific to that feature. Feature controllers sit at the feature root.
- `shared/` contains the API client, Firebase setup, and other cross-feature Dart helpers. Shared widgets live in `shared/widgets/`, and images, icons, and fonts live in `shared/assets/`.

The backend is in the top-level `functions/` directory. Firebase uses the top-level `firestore.rules` and `firestore.indexes.json`.
