import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_provider.dart';
import '../../domain/entities/client_intake_form.dart';
import '../datasources/client_intake_remote_datasource.dart';
import '../models/client_intake_model.dart';

final intakeWorkspaceRepositoryProvider = Provider<IntakeWorkspaceRepository>(
  (ref) => IntakeWorkspaceRepository(ref.watch(apiClientProvider).dio),
);

class IntakeWorkspaceRepository {
  const IntakeWorkspaceRepository(this._dio);

  final Dio _dio;

  Future<IntakeFormWorkspace> load(String uid) =>
      _requestWorkspace(uid, 'intakes/me/draft');

  Future<IntakeFormWorkspace> saveDraft(String uid, IntakeFormChange change) =>
      _requestWorkspace(
        uid,
        'intakes/me/draft',
        method: 'PUT',
        body: _body(uid, change),
      );

  Future<IntakeFormWorkspace> submit(
    String uid,
    IntakeFormChange change,
    String requestId,
  ) => _requestWorkspace(
    uid,
    'intakes/me/submit',
    method: 'POST',
    body: {..._body(uid, change), 'request_id': requestId},
  );

  Map<String, Object> _body(String uid, IntakeFormChange change) => {
    'expected_client_id': uid,
    'expected_version': change.version,
    'expected_draft_revision': change.draftRevision,
    'guardian_consent_confirmed': false,
    'answers': change.answers.map((field, value) => MapEntry(field.key, value)),
  };

  Future<IntakeFormWorkspace> _requestWorkspace(
    String uid,
    String path, {
    String method = 'GET',
    Map<String, Object>? body,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        path,
        data: body,
        options: Options(method: method),
      );
      final envelope = response.data;
      if (envelope is! Map || envelope['data'] is! Map) {
        throw const FormatException('Missing intake workspace.');
      }
      final data = envelope['data'] as Map;
      final version = _revision(data['version']);
      final rawAnswers = data['answers'];
      final latest = data['latest'];
      if (data['client_id'] != uid ||
          rawAnswers is! Map ||
          (data['profile_ready'] != null && data['profile_ready'] is! bool) ||
          (version == 0 ? latest != null : latest is! Map)) {
        throw const FormatException('Invalid intake workspace.');
      }
      final answers = <IntakeField, String>{};
      for (final field in IntakeField.values) {
        if (!rawAnswers.containsKey(field.key)) continue;
        final value = rawAnswers[field.key];
        if (value is! String) {
          throw const FormatException('Invalid intake answer.');
        }
        answers[field] = value;
      }
      final submitted = latest is Map
          ? ClientIntakeModel.fromJson(
              Map<String, dynamic>.from(latest),
              requestedClientId: uid,
            )
          : null;
      if (submitted != null && submitted.version != version) {
        throw const FormatException('Mismatched submitted version.');
      }
      return IntakeFormWorkspace(
        answers: Map.unmodifiable(answers),
        version: version,
        draftRevision: _revision(data['draft_revision']),
        profileReady: data['profile_ready'] as bool?,
        latest: submitted,
      );
    } on DioException catch (error) {
      throw intakeWorkspaceError(error);
    } on FormatException {
      throw const ClientIntakeException(
        ClientIntakeFailure.invalidData,
        'Could not read your saved intake. Please try again.',
      );
    }
  }
}

int _revision(Object? value) {
  if (value is int && value >= 0) return value;
  throw const FormatException('Invalid intake revision.');
}

ClientIntakeException intakeWorkspaceError(DioException error) {
  final response = error.response?.data;
  final detail = response is Map && response['error'] is String
      ? response['error'] as String
      : null;
  return switch (error.response?.statusCode) {
    400 => ClientIntakeException(
      ClientIntakeFailure.invalidRequest,
      detail ?? 'Check your intake answers.',
    ),
    401 => const ClientIntakeException(
      ClientIntakeFailure.unauthorized,
      'Your session ended. Please sign in again.',
    ),
    403 => const ClientIntakeException(
      ClientIntakeFailure.forbidden,
      'You do not have access to this intake.',
    ),
    404 => const ClientIntakeException(
      ClientIntakeFailure.notFound,
      'The intake is unavailable.',
    ),
    409 => ClientIntakeException(
      ClientIntakeFailure.conflict,
      detail ?? 'Your saved intake has changed.',
    ),
    null => const ClientIntakeException(
      ClientIntakeFailure.network,
      'Could not reach FitNEP. Check your connection and try again.',
    ),
    _ => const ClientIntakeException(
      ClientIntakeFailure.server,
      'The intake service is temporarily unavailable.',
    ),
  };
}
