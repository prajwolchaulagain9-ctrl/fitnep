import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';
import '../config/app_config.dart';

final firebaseInitializationProvider = FutureProvider<void>((ref) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
}, retry: (retryCount, error) => null);

// Read these after firebaseInitializationProvider has completed successfully.
// Teammates can override these providers for feature tests and emulators.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseFunctionsProvider = Provider<FirebaseFunctions>((ref) {
  final functions = FirebaseFunctions.instanceFor(
    region: AppConfig.functionsRegion,
  );
  if (kDebugMode && AppConfig.functionsEmulatorHost.isNotEmpty) {
    functions.useFunctionsEmulator(
      AppConfig.functionsEmulatorHost,
      AppConfig.functionsEmulatorPort,
      automaticHostMapping: false,
    );
  }
  return functions;
});
