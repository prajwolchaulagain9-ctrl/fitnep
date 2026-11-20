import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes/route_access_gate.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/firebase_providers.dart';
import '../../../../core/storage/token_storage.dart';
import '../../data/repositories/privacy_preferences_repository_impl.dart';
import '../../domain/entities/privacy_preferences.dart';
import '../../domain/repositories/privacy_preferences_repository.dart';

final privacyPreferencesRepositoryProvider =
    Provider.autoDispose<PrivacyPreferencesRepository>((ref) {
      final session = ref.watch(routeSessionProvider).requireValue;
      if (session?.role != FitNepRole.client) {
        throw StateError('Privacy preferences require a client account.');
      }
      final apiClient = ApiClient(
        tokenStorage: TokenStorage(
          auth: ref.watch(firebaseAuthProvider),
          expectedUid: session!.uid,
        ),
      );
      ref.onDispose(() => apiClient.dio.close());
      return PrivacyPreferencesRepositoryImpl(apiClient);
    });

final privacyPreferencesControllerProvider =
    AsyncNotifierProvider.autoDispose<
      PrivacyPreferencesController,
      PrivacyPreferences
    >(PrivacyPreferencesController.new, retry: (retryCount, error) => null);

class PrivacyPreferencesController extends AsyncNotifier<PrivacyPreferences> {
  @override
  Future<PrivacyPreferences> build() {
    return ref.watch(privacyPreferencesRepositoryProvider).loadPreferences();
  }

  Future<void> savePreferences(PrivacyPreferences preferences) async {
    final repository = ref.read(privacyPreferencesRepositoryProvider);
    final saved = await repository.savePreferences(preferences);
    if (ref.mounted &&
        identical(ref.read(privacyPreferencesRepositoryProvider), repository)) {
      state = AsyncData(saved);
    }
  }
}
