import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/client_intake.dart';
import '../models/client_intake_model.dart';

abstract class ClientIntakeRemoteDatasource {
  Future<ClientIntakeModel> getAssignedClientIntake(String clientId);

  Future<ClientIntakeModel> updateReview({
    required String clientId,
    required ClientIntakeReviewAction action,
    String? note,
  });
}

class ClientIntakeRemoteDatasourceImpl implements ClientIntakeRemoteDatasource {
  const ClientIntakeRemoteDatasourceImpl(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ClientIntakeModel> getAssignedClientIntake(String clientId) async {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw const ClientIntakeException(
        ClientIntakeFailure.configuration,
        'The mobile app is not connected to the FitNep API.',
      );
    }
    try {
      final response = await _apiClient.dio.get<Object?>(
        AppConstants.dietitianClientIntakeEndpoint(clientId),
      );
      return _modelFromResponse(response.data, clientId);
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const ClientIntakeException(
        ClientIntakeFailure.invalidData,
        'The saved intake form could not be displayed.',
      );
    }
  }

  @override
  Future<ClientIntakeModel> updateReview({
    required String clientId,
    required ClientIntakeReviewAction action,
    String? note,
  }) async {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw const ClientIntakeException(
        ClientIntakeFailure.configuration,
        'The mobile app is not connected to the FitNep API.',
      );
    }
    try {
      final data = <String, Object?>{'action': _reviewActionName(action)};
      if (note case final reviewNote?) data['note'] = reviewNote;
      final response = await _apiClient.dio.patch<Object?>(
        AppConstants.dietitianClientIntakeReviewEndpoint(clientId),
        data: data,
      );
      return _modelFromResponse(response.data, clientId);
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const ClientIntakeException(
        ClientIntakeFailure.invalidData,
        'The saved intake form could not be displayed.',
      );
    }
  }

  ClientIntakeModel _modelFromResponse(Object? response, String clientId) {
    Object? payload = response;
    if (payload is Map) payload = payload['data'];
    if (payload is Map) payload = payload['intake'];
    if (payload is! Map) {
      throw const FormatException('Expected an intake object.');
    }
    return ClientIntakeModel.fromJson(
      Map<String, dynamic>.from(payload),
      requestedClientId: clientId,
    );
  }

  String _reviewActionName(ClientIntakeReviewAction action) => switch (action) {
    ClientIntakeReviewAction.reviewed => 'reviewed',
    ClientIntakeReviewAction.missingInformation => 'missing_information',
    ClientIntakeReviewAction.clarificationRequested =>
      'clarification_requested',
  };

  ClientIntakeException _mapDioException(DioException error) {
    return switch (error.response?.statusCode) {
      401 => const ClientIntakeException(
        ClientIntakeFailure.unauthorized,
        'Your session has expired. Please sign in again.',
      ),
      403 => const ClientIntakeException(
        ClientIntakeFailure.forbidden,
        'This client is not currently assigned to you.',
      ),
      404 => const ClientIntakeException(
        ClientIntakeFailure.notFound,
        'This client has not submitted an intake form yet.',
      ),
      400 => ClientIntakeException(
        ClientIntakeFailure.invalidRequest,
        _apiError(error) ?? 'The intake review request is invalid.',
      ),
      _ when _isNetworkFailure(error) => const ClientIntakeException(
        ClientIntakeFailure.network,
        'Could not load the intake form. Check your connection and try again.',
      ),
      _ => const ClientIntakeException(
        ClientIntakeFailure.server,
        'Could not load the intake form right now. Please try again.',
      ),
    };
  }

  bool _isNetworkFailure(DioException error) =>
      error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout;

  String? _apiError(DioException error) {
    final data = error.response?.data;
    if (data is! Map || data['error'] is! String) return null;
    final message = (data['error'] as String).trim();
    return message.isEmpty ? null : message;
  }
}

enum ClientIntakeFailure {
  configuration,
  unauthorized,
  forbidden,
  notFound,
  invalidRequest,
  network,
  invalidData,
  server,
}

class ClientIntakeException implements Exception {
  const ClientIntakeException(this.failure, this.message);

  final ClientIntakeFailure failure;
  final String message;

  bool get canRetry => switch (failure) {
    ClientIntakeFailure.network ||
    ClientIntakeFailure.invalidData ||
    ClientIntakeFailure.server => true,
    _ => false,
  };

  @override
  String toString() => message;
}
