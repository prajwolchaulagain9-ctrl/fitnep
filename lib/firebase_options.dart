// Client configuration downloaded from Firebase project fitnep-88908.
// These identifiers are not server credentials. Access is controlled by Auth,
// Firestore rules and trusted server authorization.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'FitNEP Firebase is configured for Android and iOS.',
      );
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS => ios,
      _ => throw UnsupportedError(
        'FitNEP Firebase is configured for Android and iOS.',
      ),
    };
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyB1osBZADes1iRhYvonewMgTwcjUUOTPTE',
    appId: '1:1005066655980:android:439e90e7ff1e252483edc9',
    messagingSenderId: '1005066655980',
    projectId: 'fitnep-88908',
    storageBucket: 'fitnep-88908.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyBogN_EXrlu55GAYaihZBiryjj2Oa0SuTY',
    appId: '1:1005066655980:ios:b66d19dd781a157b83edc9',
    messagingSenderId: '1005066655980',
    projectId: 'fitnep-88908',
    storageBucket: 'fitnep-88908.firebasestorage.app',
    iosBundleId: 'com.example.fitnep',
  );
}
