import 'dart:async';

import 'package:fitnep/features/authentication/domain/entities/privacy_preferences.dart';
import 'package:fitnep/features/authentication/domain/repositories/privacy_preferences_repository.dart';
import 'package:fitnep/features/authentication/presentation/controllers/privacy_preferences_controller.dart';
import 'package:fitnep/features/authentication/presentation/pages/privacy_preferences_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reloads consent when a withdrawal response is lost', (
    tester,
  ) async {
    final repository = _LostResponseRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          privacyPreferencesRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: PrivacyPreferencesPage()),
      ),
    );
    await tester.pumpAndSettle();

    final option = find.widgetWithText(SwitchListTile, 'Share progress photos');
    final toggle = find.descendant(of: option, matching: find.byType(Switch));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(option).value, isTrue);
    await tester.tap(toggle.hitTestable());
    await tester.pump();
    await tester.pump();
    expect(option, findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.reload.complete(repository.saved);
    await tester.pumpAndSettle();
    await tester.ensureVisible(toggle);
    expect(tester.widget<SwitchListTile>(option).value, isFalse);
  });
}

class _LostResponseRepository implements PrivacyPreferencesRepository {
  var saved = const PrivacyPreferences(shareProgressPhotos: true);
  final reload = Completer<PrivacyPreferences>();
  var initialLoad = true;

  @override
  Future<PrivacyPreferences> loadPreferences() async {
    if (!initialLoad) return reload.future;
    initialLoad = false;
    return saved;
  }

  @override
  Future<PrivacyPreferences> setSharing(
    PrivacySharingCategory category,
    bool enabled,
  ) async {
    expect(category, PrivacySharingCategory.progressPhotos);
    saved = PrivacyPreferences(shareProgressPhotos: enabled);
    throw TimeoutException('Save response lost');
  }
}
