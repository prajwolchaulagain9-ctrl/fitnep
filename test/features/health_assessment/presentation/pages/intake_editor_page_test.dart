import 'package:dio/dio.dart';
import 'package:fitnep/features/health_assessment/data/repositories/intake_workspace_repository.dart';
import 'package:fitnep/features/health_assessment/presentation/pages/intake_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('loads a partial draft and saves a minor’s confirmation', (
    tester,
  ) async {
    final api = _IntakeApi();
    await _open(tester, api);
    final name = find.byKey(const ValueKey('full_name'));
    expect(tester.widget<TextFormField>(name).controller!.text, 'Saved Name');
    await tester.enterText(find.byKey(const ValueKey('age')), '17');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Parent or guardian consent'), findsOneWidget);
    await tester.tap(find.text('Confirm permission'));
    await tester.pumpAndSettle();

    await _tap(tester, 'Save draft');
    expect(api.lastDraft?['expected_client_id'], 'client-1');
    expect(api.lastDraft?['expected_version'], 0);
    expect(api.lastDraft?['expected_draft_revision'], 1);
    expect(api.lastDraft?['guardian_consent_confirmed'], true);
    expect(api.lastDraft?['answers'], {'full_name': 'Saved Name', 'age': '17'});
    expect(find.text('Draft saved.'), findsOneWidget);
  });

  testWidgets(
    'retries resubmission with the same request ID after a lost response',
    (tester) async {
      final api = _IntakeApi()..prepareRequestedRevision();
      await _open(tester, api);
      expect(find.text('Pending information'), findsOneWidget);
      expect(find.text('Update your goals.'), findsOneWidget);
      final goals = find.byKey(const ValueKey('fitness_goals'));
      await tester.ensureVisible(goals);
      await tester.enterText(goals, 'Improve endurance');
      await tester.pumpAndSettle();

      await _tap(tester, 'Submit updated intake');
      await _tap(tester, 'Submit updated intake');
      expect(api.submissions, hasLength(2));
      expect(api.submissions.first, api.submissions.last);
      expect(api.submissions.last['expected_version'], 1);
      expect(
        api.submissions.last['request_id'],
        matches(RegExp(r'^[a-f0-9]{32}$')),
      );
      expect(
        find.text('Intake submitted. Your care team can review it.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('inactive membership keeps the intake editor closed', (
    tester,
  ) async {
    final api = _IntakeApi()..membershipActive = false;
    await _open(tester, api);
    expect(
      find.text('An active membership is required to edit your intake.'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });
}

Future<void> _open(WidgetTester tester, _IntakeApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        intakeWorkspaceRepositoryProvider.overrideWithValue(api.repository),
      ],
      child: const MaterialApp(home: IntakeEditorPage(clientId: 'client-1')),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

class _IntakeApi {
  _IntakeApi() {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _handle));
  }

  final _dio = Dio(BaseOptions(baseUrl: 'https://example.test/'));
  IntakeWorkspaceRepository get repository => IntakeWorkspaceRepository(_dio);
  Map<String, dynamic> _answers = {'full_name': 'Saved Name'};
  Map<String, dynamic>? lastDraft;
  final submissions = <Map<String, dynamic>>[];
  var membershipActive = true;
  var _guardian = false;
  var _version = 0;
  var _draftRevision = 1;
  var _pending = false;

  void prepareRequestedRevision() {
    final year = DateTime.now().toUtc().year - 25;
    _version = 1;
    _draftRevision = 0;
    _pending = true;
    _answers = {
      'full_name': 'Saved Name',
      'age': '25',
      'date_of_birth': '$year-01-01',
      'contact_email': 'client@example.test',
      'height_cm': '175',
      'weight_kg': '70',
      'fitness_goals': 'Stay active',
      'medical_history': 'None',
      'allergies': 'None',
      'dietary_restrictions': 'None',
      'food_preferences': 'Rice',
    };
  }

  void _handle(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'PUT') {
      lastDraft = Map<String, dynamic>.from(options.data as Map);
      _answers = Map<String, dynamic>.from(lastDraft!['answers'] as Map);
      _guardian = lastDraft!['guardian_consent_confirmed'] as bool;
      _draftRevision++;
    } else if (options.method == 'POST') {
      final request = Map<String, dynamic>.from(options.data as Map);
      submissions.add(request);
      if (submissions.length == 1) {
        _version++;
        _pending = false;
        _answers = Map<String, dynamic>.from(request['answers'] as Map);
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          ),
        );
        return;
      }
    }
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'data': {
            'client_id': 'client-1',
            'answers': _answers,
            'membership_active': membershipActive,
            'guardian_consent_confirmed': _guardian,
            'version': _version,
            'draft_revision': _draftRevision,
            'latest': _version == 0
                ? null
                : {
                    'client_id': 'client-1',
                    'version': _version,
                    'status': _pending ? 'information_requested' : 'submitted',
                    'review_note': _pending ? 'Update your goals.' : null,
                    'allergies': [],
                    'medical_conditions': [],
                    'sections': [],
                  },
          },
        },
      ),
    );
  }
}
