import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/firebase_providers.dart';
import '../domain/entities/privacy_policy.dart';
import 'hosted_auth_client.dart';

typedef RegistrationPrivacyRequest = Future<bool> Function(
  Map<String, Object> data,
);

final registrationPrivacyProvider = Provider<RegistrationPrivacyRequest>((ref) {
  if (AppConfig.hostedSessionsEnabled) {
    final request = ref.watch(hostedAuthRequestProvider);
    return (data) async =>
        (await request('auth/privacy', data))['accepted'] == true;
  }
  final endpoint = _privacyCallable(
    ref.watch(firebaseFunctionsProvider),
    AppConfig.signupPrivacyUrl,
  );
  return (data) async {
    final response = await endpoint.call(data);
    return response.data is Map && response.data['accepted'] == true;
  };
});

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
    .family<bool, String>((ref, uid) async {
      final request = ref.watch(registrationPrivacyProvider);
      final store = ref.watch(pendingRegistrationConsentStoreProvider);
      final accepted = await request({'uid': uid, 'action': 'status'});
      final pending = await store.read(uid);
      if (pending == null) return accepted;
      if (!accepted) {
        if (!ref.mounted) return false;
        await acceptRegistrationPrivacy(request, uid, pending);
      }
      await store.clear(uid);
      return true;
    }, retry: (retryCount, error) => null);

Future<void> acceptRegistrationPrivacy(
  RegistrationPrivacyRequest request,
  String uid,
  RegistrationConsent consent,
) async {
  final result = await request({
    'action': 'accept',
    'uid': uid,
    'age': consent.age,
    'privacy_policy_version': privacyPolicyVersion,
    'privacy_policy_accepted': true,
    'guardian_consent_confirmed': consent.guardianConfirmed,
  });
  if (!result) {
    throw StateError('Consent was not saved.');
  }
}

final pendingRegistrationConsentStoreProvider =
    Provider<PendingRegistrationConsentStore>(
      (ref) => const PendingRegistrationConsentStore(),
    );

class PendingRegistrationConsentStore {
  const PendingRegistrationConsentStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  String _key(String uid) => 'pending_registration_consent_$uid';

  Future<void> write(String uid, RegistrationConsent consent) => _storage.write(
    key: _key(uid),
    value: '$privacyPolicyVersion:${consent.age}:${consent.guardianConfirmed}',
  );

  Future<RegistrationConsent?> read(String uid) async {
    final String? value;
    try {
      value = await _storage.read(key: _key(uid));
    } on Exception {
      // A device without secure storage can finish via the age and policy form.
      return null;
    }
    if (value?.split(':') case [
      privacyPolicyVersion,
      final years,
      final guardian,
    ]) {
      final age = parseRegistrationAge(years);
      if (age != null && (age >= 18 || guardian == 'true')) {
        return (age: age, guardianConfirmed: age < 18);
      }
    }
    return null;
  }

  Future<void> clear(String uid) async {
    try {
      await _storage.delete(key: _key(uid));
    } on Exception {
      // Firebase is authoritative once acceptance has been saved.
    }
  }
}
