import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/firebase_providers.dart';
import '../domain/entities/privacy_policy.dart';

typedef RegistrationPrivacyRequest = Future<bool> Function(
  Map<String, Object> data,
);

final registrationPrivacyProvider = Provider<RegistrationPrivacyRequest>((ref) {
  if (!AppConfig.useFirebaseEmulators &&
      (AppConfig.signupPrivacyUrl.isNotEmpty ||
          (kDebugMode && AppConfig.functionsEmulatorHost.isNotEmpty))) {
    final endpoint = _privacyCallable(
      ref.watch(firebaseFunctionsProvider),
      AppConfig.signupPrivacyUrl,
    );
    return (data) async {
      final response = await endpoint.call(data);
      return response.data['accepted'] as bool;
    };
  }

  final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  return (data) async {
    final uid = data['uid'] as String;
    final user = auth.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('The signed-in account changed.');
    }
    final token = await user.getIdTokenResult();
    final role = token.claims?['role'];
    if (role is String &&
        const {
          'admin',
          'dietitian',
          'staff',
        }.contains(role.trim().toLowerCase())) {
      return true;
    }

    final document = firestore.collection('privacy_acceptances').doc(uid);
    if (data['action'] == 'status') {
      final snapshot = await document.get(
        const GetOptions(source: Source.server),
      );
      return _hasAccepted(snapshot);
    }
    final age = data['age'];
    if (data['action'] != 'accept' ||
        data['privacy_policy_version'] != privacyPolicyVersion ||
        data['privacy_policy_accepted'] != true ||
        age is! int ||
        age < 1 ||
        age > 120 ||
        (age < 18 && data['guardian_consent_confirmed'] != true)) {
      throw StateError('Valid privacy and guardian consent are required.');
    }
    await firestore.runTransaction((transaction) async {
      if (_hasAccepted(await transaction.get(document))) return;
      final isMinor = age < 18;
      transaction.set(document, {
        'policy_version': privacyPolicyVersion,
        'accepted_at': FieldValue.serverTimestamp(),
        'age_at_acceptance': age,
        'guardian_consent_confirmed': isMinor,
        if (isMinor)
          'guardian_consent_confirmed_at': FieldValue.serverTimestamp(),
      });
    });
    return true;
  };
});

bool _hasAccepted(DocumentSnapshot<Map<String, dynamic>> snapshot) {
  final data = snapshot.data();
  return data?['policy_version'] == privacyPolicyVersion &&
      data?['accepted_at'] is Timestamp;
}

HttpsCallable _privacyCallable(FirebaseFunctions functions, String url) {
  if (url.isEmpty) return functions.httpsCallable('registrationPrivacy');
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Expected an HTTPS privacy endpoint URL.');
  }
  return functions.httpsCallableFromUrl(url);
}

final registrationAcceptedProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, uid) => ref.watch(registrationPrivacyProvider)({
        'uid': uid,
        'action': 'status',
      }),
      retry: (retryCount, error) => null,
    );

Future<void> acceptRegistrationPrivacy(
  WidgetRef ref,
  String uid,
  int age,
  bool accepted,
  bool guardian,
) async {
  final result = await ref.read(registrationPrivacyProvider).call({
    'action': 'accept',
    'uid': uid,
    'age': age,
    'privacy_policy_version': privacyPolicyVersion,
    'privacy_policy_accepted': accepted,
    'guardian_consent_confirmed': guardian,
  });
  if (!result) {
    throw StateError('Consent was not saved.');
  }
}
