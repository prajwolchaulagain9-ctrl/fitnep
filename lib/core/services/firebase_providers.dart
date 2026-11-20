import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';
import '../config/app_config.dart';

final firebaseInitializationProvider = FutureProvider<void>((ref) async {
  if (AppConfig.useFirebaseEmulators) {
    if (![
      '127.0.0.1',
      'localhost',
      '10.0.2.2',
    ].contains(AppConfig.emulatorHost)) {
      throw StateError('The free demo must use a local emulator host.');
    }
    final options = DefaultFirebaseOptions.currentPlatform;
    final app = Firebase.apps.any((app) => app.name == 'fitnep-demo')
        ? Firebase.app('fitnep-demo')
        : await Firebase.initializeApp(
            name: 'fitnep-demo',
            options: FirebaseOptions(
              apiKey: options.apiKey,
              appId: options.appId,
              messagingSenderId: options.messagingSenderId,
              projectId: 'demo-fitnep',
            ),
          );
    await FirebaseAuth.instanceFor(app: app).useAuthEmulator(
      AppConfig.emulatorHost,
      9099,
      automaticHostMapping: false,
    );
    FirebaseFirestore.instanceFor(app: app).useFirestoreEmulator(
      AppConfig.emulatorHost,
      18080,
      automaticHostMapping: false,
    );
    FirebaseFunctions.instanceFor(
      app: app,
      region: AppConfig.functionsRegion,
    ).useFunctionsEmulator(
      AppConfig.emulatorHost,
      5001,
      automaticHostMapping: false,
    );
    return;
  }
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}, retry: (retryCount, error) => null);

// Read these after firebaseInitializationProvider has completed successfully.
// Teammates can override these providers for feature tests and emulators.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instanceFor(app: _activeApp()),
);

FirebaseApp _activeApp() =>
    Firebase.app(AppConfig.useFirebaseEmulators ? 'fitnep-demo' : '[DEFAULT]');

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instanceFor(app: _activeApp()),
);

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(
    app: _activeApp(),
    region: AppConfig.functionsRegion,
  );
});
