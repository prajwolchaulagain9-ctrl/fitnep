import 'package:fitnep/features/admin/pages/client_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitnep/features/admin/data/admin_local_datasource.dart';
import 'package:fitnep/features/admin/client_list_controller.dart';

void main() {
  testWidgets('compact app bar keeps search controls from overlapping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminDatasourceProvider.overrideWithValue(AdminLocalDatasource()),
        ],
        child: const MaterialApp(home: ClientListPage()),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Search clients'), findsOneWidget);
    expect(find.byTooltip('More options'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Package Management'), findsOneWidget);
    await tester.tapAt(const Offset(8, 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search clients'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Search by name...'), findsOneWidget);
    expect(find.byTooltip('Filter'), findsNothing);
    expect(find.byTooltip('More options'), findsNothing);
    expect(tester.takeException(), isNull);

    // Let the local datasource's initial 400 ms load finish before teardown.
    await tester.pump(const Duration(milliseconds: 200));
  });
}
