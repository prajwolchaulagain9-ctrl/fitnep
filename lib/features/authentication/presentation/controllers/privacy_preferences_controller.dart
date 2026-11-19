import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/privacy_preferences_local_datasource.dart';
import '../../data/repositories/privacy_preferences_repository_impl.dart';
import '../../domain/entities/privacy_preferences.dart';
import '../../domain/repositories/privacy_preferences_repository.dart';

final privacyPreferencesLocalDatasourceProvider =
    Provider<PrivacyPreferencesLocalDatasource>(
      (ref) => const PrivacyPreferencesLocalDatasource(),
    );

final privacyPreferencesRepositoryProvider =
    Provider<PrivacyPreferencesRepository>(
      (ref) => PrivacyPreferencesRepositoryImpl(
        ref.watch(privacyPreferencesLocalDatasourceProvider),
      ),
    );

final privacyPreferencesControllerProvider =
    AsyncNotifierProvider<PrivacyPreferencesController, PrivacyPreferences>(
      PrivacyPreferencesController.new,
    );

class PrivacyPreferencesController extends AsyncNotifier<PrivacyPreferences> {
  @override
  Future<PrivacyPreferences> build() {
    return ref.watch(privacyPreferencesRepositoryProvider).loadPreferences();
  }

  Future<void> savePreferences(PrivacyPreferences preferences) async {
    await ref
        .read(privacyPreferencesRepositoryProvider)
        .savePreferences(preferences);
    state = AsyncData(preferences);
  }
}
