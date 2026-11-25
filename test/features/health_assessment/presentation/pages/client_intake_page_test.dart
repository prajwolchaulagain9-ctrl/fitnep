import 'package:fitnep/app/theme/app_theme.dart';
import 'package:fitnep/features/health_assessment/domain/entities/client_intake.dart';
import 'package:fitnep/features/health_assessment/domain/repositories/client_intake_repository.dart';
import 'package:fitnep/features/health_assessment/presentation/controllers/client_intake_controller.dart';
import 'package:fitnep/features/health_assessment/presentation/pages/client_intake_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dietitian marks an intake form as reviewed', (tester) async {
    final repository = _FakeClientIntakeRepository();
    await _pumpPage(tester, repository);

    final action = find.widgetWithText(FilledButton, 'Mark as reviewed');
    await tester.scrollUntilVisible(action, 300);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark reviewed'));
    await tester.pumpAndSettle();

    expect(repository.lastAction, ClientIntakeReviewAction.reviewed);
    expect(repository.current.status, ClientIntakeStatus.reviewed);
    expect(find.text('Reviewed'), findsOneWidget);
  });

  testWidgets('dietitian requests and saves missing information', (
    tester,
  ) async {
    final repository = _FakeClientIntakeRepository();
    await _pumpPage(tester, repository);

    final action = find.widgetWithText(
      OutlinedButton,
      'Request missing information',
    );
    await tester.scrollUntilVisible(action, 300);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Please provide the current medication dosage.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(repository.lastAction, ClientIntakeReviewAction.missingInformation);
    expect(
      repository.lastNote,
      'Please provide the current medication dosage.',
    );
    expect(repository.current.status, ClientIntakeStatus.informationRequested);
    expect(find.text('More information required'), findsOneWidget);
    expect(
      find.text('Please provide the current medication dosage.'),
      findsOneWidget,
    );
  });

  testWidgets('dietitian requests clarification for unclear information', (
    tester,
  ) async {
    final repository = _FakeClientIntakeRepository();
    await _pumpPage(tester, repository);

    final action = find.widgetWithText(OutlinedButton, 'Request clarification');
    await tester.scrollUntilVisible(action, 300);
    await tester.tap(action);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Please clarify the reported allergy reaction.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(
      repository.lastAction,
      ClientIntakeReviewAction.clarificationRequested,
    );
    expect(repository.current.status, ClientIntakeStatus.informationRequested);
    expect(
      find.text('Clarification has been requested from the client.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  ClientIntakeRepository repository,
) async {
  tester.view.physicalSize = const Size(1080, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [clientIntakeRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ClientIntakePage(clientId: 'client-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeClientIntakeRepository implements ClientIntakeRepository {
  ClientIntakeReviewAction? lastAction;
  String? lastNote;
  ClientIntake current = const ClientIntake(
    clientId: 'client-1',
    allergies: ['Peanuts'],
    medicalConditions: ['Type 2 diabetes'],
    sections: [
      ClientIntakeSection(
        title: 'Health information',
        fields: [ClientIntakeField(label: 'Height', value: '168 cm')],
      ),
    ],
    submittedAt: null,
    updatedAt: null,
  );

  @override
  Future<ClientIntake> getAssignedClientIntake(String clientId) async =>
      current;

  @override
  Future<ClientIntake> updateReview({
    required String clientId,
    required ClientIntakeReviewAction action,
    String? note,
    int? expectedVersion,
  }) async {
    lastAction = action;
    lastNote = note;
    current = ClientIntake(
      clientId: current.clientId,
      allergies: current.allergies,
      medicalConditions: current.medicalConditions,
      sections: current.sections,
      submittedAt: current.submittedAt,
      updatedAt: current.updatedAt,
      status: action == ClientIntakeReviewAction.reviewed
          ? ClientIntakeStatus.reviewed
          : ClientIntakeStatus.informationRequested,
      reviewAction: action,
      reviewNote: note,
      reviewUpdatedAt: DateTime(2026, 11, 25, 10),
    );
    return current;
  }
}
