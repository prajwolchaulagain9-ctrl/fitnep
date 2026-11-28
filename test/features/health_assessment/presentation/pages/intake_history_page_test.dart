import 'dart:async';

import 'package:fitnep/features/health_assessment/data/intake_history_repository.dart';
import 'package:fitnep/features/health_assessment/pages/intake_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _History extends Fake implements IntakeHistoryRepository {
  final pending = <String, Completer<IntakeHistoryPageData>>{};

  @override
  Future<IntakeHistoryPageData> listVersions(String clientId, {int? before}) {
    final result = Completer<IntakeHistoryPageData>();
    pending[clientId] = result;
    return result.future;
  }
}

void main() {
  testWidgets('history ignores a delayed result after switching clients', (
    tester,
  ) async {
    final history = _History();
    final client = ValueNotifier('first');
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [intakeHistoryRepositoryProvider.overrideWithValue(history)],
        child: MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: client,
            builder: (_, id, _) =>
                IntakeHistoryPage(clientId: id, openVersion: (_, _) async {}),
          ),
        ),
      ),
    );
    client.value = 'second';
    await tester.pump();
    history.pending['second']!.complete((
      versions: [(version: 2, submittedAt: null)],
      nextBefore: null,
    ));
    await tester.pumpAndSettle();
    history.pending['first']!.complete((
      versions: [(version: 1, submittedAt: null)],
      nextBefore: null,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Version 2'), findsOneWidget);
    expect(find.text('Version 1'), findsNothing);
  });
}
