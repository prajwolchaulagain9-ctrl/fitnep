import 'package:dio/dio.dart';
import 'package:fitnep/features/authorization/data/authorization_repository.dart';
import 'package:fitnep/features/health_assessment/data/intake_workspace_repository.dart';
import 'package:fitnep/features/health_assessment/pages/intake_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'direct entry opens the form and verifies age on the first save',
    (tester) async {
      final api = _IntakeApi()..profileReady = false;
      await _open(tester, api);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('height_cm')), '175');
      await tester.enterText(find.byKey(const ValueKey('weight_kg')), '70');
      await _tap(tester, 'Next');
      expect(find.text('Confirm your date of birth'), findsOneWidget);
      expect(api.lastDraft, isNull);
      await _tap(tester, 'Cancel');
      expect(find.text('22.9 kg/m²'), findsOneWidget);
      await _tap(tester, 'Next');
      final year = DateTime.now().toUtc().year - 17;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Date of birth'),
        '$year-01-01',
      );
      await _tap(tester, 'Save and continue');
      expect(find.text('Parent or guardian consent'), findsOneWidget);
      expect(api.lastDraft, isNull);
      await _tap(tester, 'Confirm permission');
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(api.profileUpdate, {
        'expected_client_id': 'client-1',
        'date_of_birth': '$year-01-01',
        'guardian_consent_confirmed': true,
      });
      expect(api.lastDraft?['answers'], {
        'height_cm': '175',
        'weight_kg': '70',
      });
    },
  );

  testWidgets('a partial draft cannot be submitted with allergies blank', (
    tester,
  ) async {
    final api = _IntakeApi()..prepareRequestedRevision();
    await _open(tester, api);
    for (var i = 0; i < 2; i++) {
      await _tap(tester, 'Next');
    }
    final allergies = find.byKey(const ValueKey('allergies'));
    await tester.ensureVisible(allergies);
    await tester.enterText(allergies, '');
    await tester.pumpAndSettle();

    await _tap(tester, 'Submit updated intake');
    expect(find.text('Food allergies is required.'), findsOneWidget);
    expect(api.submissions, isEmpty);
    await _tap(tester, 'Save draft');
    expect(api.lastDraft?['answers'], isNot(contains('allergies')));
  });

  testWidgets(
    'retries resubmission with the same request ID after a lost response',
    (tester) async {
      final api = _IntakeApi()..prepareRequestedRevision();
      await _open(tester, api);
      expect(find.text('Pending information'), findsOneWidget);
      expect(find.text('Update your goals.'), findsOneWidget);
      await _tap(tester, 'Next');
      final goals = find.byKey(const ValueKey('fitness_goals'));
      await tester.ensureVisible(goals);
      await tester.enterText(goals, 'Improve endurance');
      await tester.pumpAndSettle();
      await _tap(tester, 'Next');

      await _tap(tester, 'Submit updated intake');
      await _tap(tester, 'Submit updated intake');
      expect(api.submissions, hasLength(2));
      expect(api.submissions.first, api.submissions.last);
      expect(api.submissions.last['expected_version'], 1);
      expect(api.submissions.last['answers']['waist_cm'], '78');
      expect(
        api.submissions.last['request_id'],
        matches(RegExp(r'^[a-f0-9]{32}$')),
      );
      expect(find.text('Health intake submitted.'), findsOneWidget);
    },
  );

  testWidgets(
    'an unpaid client can complete steps and resume the saved draft',
    (tester) async {
      final api = _IntakeApi()..membershipActive = false;
      await _open(tester, api);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('full_name')), findsNothing);
      expect(find.byKey(const ValueKey('waist_cm')), findsNothing);
      expect(find.byKey(const ValueKey('hip_cm')), findsNothing);
      expect(find.byKey(const ValueKey('chest_cm')), findsNothing);
      expect(find.byIcon(Icons.height_rounded), findsOneWidget);
      expect(find.byIcon(Icons.monitor_weight_outlined), findsOneWidget);
      expect(find.byIcon(Icons.speed_rounded), findsOneWidget);
      expect(
        find.text('Enter your height and weight to see your estimate.'),
        findsOneWidget,
      );
      await _tap(tester, 'Next');
      expect(find.text('Height (cm) is required.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('height_cm')), '175');
      await tester.enterText(find.byKey(const ValueKey('weight_kg')), '70');
      await tester.pump();
      expect(find.text('22.9 kg/m²'), findsOneWidget);
      await _tap(tester, 'Next');
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(api.lastDraft?['answers'], {
        'height_cm': '175',
        'weight_kg': '70',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _open(tester, api);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      await _tap(tester, 'Back');
      expect(find.text('22.9 kg/m²'), findsOneWidget);
    },
  );

  testWidgets('prefills onboarding values only for an untouched intake', (
    tester,
  ) async {
    final api = _IntakeApi()
      .._draftRevision = 0
      ..onboarding = {'status': 'completed', 'heightCm': 175, 'weightKg': 70};
    await _open(tester, api);
    expect(find.text('22.9 kg/m²'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('weight_kg')), '75');
    await _tap(tester, 'Save draft');

    await tester.pumpWidget(const SizedBox.shrink());
    await _open(tester, api);
    await _tap(tester, 'Back');
    expect(find.text('75'), findsOneWidget);
    expect(find.text('24.5 kg/m²'), findsOneWidget);
  });
}

Future<void> _open(WidgetTester tester, _IntakeApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        intakeWorkspaceRepositoryProvider.overrideWithValue(api.repository),
        authorizationRepositoryProvider.overrideWithValue(_ProfileApi(api)),
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

class _ProfileApi extends Fake implements AuthorizationRepository {
  _ProfileApi(this.api);

  final _IntakeApi api;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    expect(path, 'profile/me');
    if (method == 'PATCH') {
      api.profileUpdate = data;
      api.profileReady = true;
    }
    return {
      'account': {'id': 'client-1'},
      'onboarding': ?api.onboarding,
    };
  }
}

class _IntakeApi {
  _IntakeApi() {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _handle));
  }

  final _dio = Dio(BaseOptions(baseUrl: 'https://example.test/'));
  IntakeWorkspaceRepository get repository => IntakeWorkspaceRepository(_dio);
  Map<String, dynamic> _answers = {'full_name': 'Saved Name'};
  Map<String, dynamic>? lastDraft;
  Map<String, dynamic>? profileUpdate;
  Map<String, dynamic>? onboarding;
  final submissions = <Map<String, dynamic>>[];
  var membershipActive = true;
  var profileReady = true;
  var _version = 0;
  var _draftRevision = 1;
  var _pending = false;

  void prepareRequestedRevision() {
    _version = 1;
    _draftRevision = 0;
    _pending = true;
    _answers = {
      'full_name': 'Saved Name',
      'age': '25',
      'date_of_birth': '2000-01-01',
      'contact_email': 'client@example.test',
      'height_cm': '175',
      'weight_kg': '70',
      'waist_cm': '78',
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
      _draftRevision++;
    } else if (options.method == 'POST') {
      final request = Map<String, dynamic>.from(options.data as Map);
      submissions.add(request);
      if (submissions.length == 1) {
        _version++;
        _draftRevision = 0;
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
            'profile_ready': profileReady,
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
