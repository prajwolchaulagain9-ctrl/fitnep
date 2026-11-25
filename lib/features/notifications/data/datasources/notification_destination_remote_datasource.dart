import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/notification_entity.dart';
import '../models/notification_destination_record_model.dart';

abstract class NotificationDestinationRemoteDatasource {
  Future<NotificationDestinationRecordModel> getRecord(
    NotificationType type,
    String referenceId,
  );
}

class NotificationDestinationRemoteDatasourceImpl
    implements NotificationDestinationRemoteDatasource {
  final ApiClient _apiClient;

  const NotificationDestinationRemoteDatasourceImpl(this._apiClient);

  @override
  Future<NotificationDestinationRecordModel> getRecord(
    NotificationType type,
    String referenceId,
  ) async {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw const NotificationDestinationException(
        NotificationDestinationFailure.configuration,
        'The mobile app is not connected to the FitNep API.',
      );
    }

    final endpoint = _endpointFor(type, referenceId);

    try {
      final response = await _apiClient.dio.get<Object?>(endpoint);
      final record = _extractRecord(response.data, type);
      return NotificationDestinationRecordModel.fromJson(
        record,
        type: type,
        referenceId: referenceId,
      );
    } on DioException catch (error) {
      throw _mapDioException(error, type);
    } on FormatException {
      throw NotificationDestinationException(
        NotificationDestinationFailure.invalidData,
        'The ${_label(type)} could not be loaded because the server returned invalid data.',
      );
    }
  }

  String _endpointFor(NotificationType type, String referenceId) {
    return switch (type) {
      NotificationType.dietPlan => AppConstants.dietPlanEndpoint(referenceId),
      NotificationType.message => AppConstants.conversationEndpoint(
        referenceId,
      ),
      NotificationType.task => AppConstants.taskEndpoint(referenceId),
      NotificationType.payment => AppConstants.paymentEndpoint(referenceId),
      NotificationType.assignment =>
        AppConstants.dietitianAssignedClientEndpoint(referenceId),
      NotificationType.intake ||
      NotificationType.membership ||
      NotificationType.other => throw const NotificationDestinationException(
        NotificationDestinationFailure.invalidReference,
        'This notification does not have a supported destination.',
      ),
    };
  }

  Map<String, dynamic> _extractRecord(
    Object? responseData,
    NotificationType type,
  ) {
    Object? payload = responseData;
    if (payload is Map && payload['data'] != null) {
      payload = payload['data'];
    }

    final recordKey = switch (type) {
      NotificationType.dietPlan => 'diet_plan',
      NotificationType.message => 'conversation',
      NotificationType.task => 'task',
      NotificationType.payment => 'payment',
      NotificationType.assignment => 'client',
      NotificationType.intake ||
      NotificationType.membership ||
      NotificationType.other => 'record',
    };

    if (payload is Map && payload[recordKey] != null) {
      payload = payload[recordKey];
    }
    if (payload is! Map) {
      throw const FormatException('Expected a related record object.');
    }
    return Map<String, dynamic>.from(payload);
  }

  NotificationDestinationException _mapDioException(
    DioException error,
    NotificationType type,
  ) {
    final label = _label(type);
    return switch (error.response?.statusCode) {
      401 => const NotificationDestinationException(
        NotificationDestinationFailure.unauthorized,
        'Your session has expired. Please sign in again.',
      ),
      403 => NotificationDestinationException(
        NotificationDestinationFailure.forbidden,
        'You do not have permission to view this $label.',
      ),
      404 => NotificationDestinationException(
        NotificationDestinationFailure.notFound,
        'This $label is no longer available. It may have been deleted.',
      ),
      _ when _isNetworkFailure(error) => NotificationDestinationException(
        NotificationDestinationFailure.network,
        'Could not load this $label. Check your connection and try again.',
      ),
      _ => NotificationDestinationException(
        NotificationDestinationFailure.server,
        'Could not load this $label right now. Please try again.',
      ),
    };
  }

  bool _isNetworkFailure(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }

  String _label(NotificationType type) => switch (type) {
    NotificationType.dietPlan => 'diet plan',
    NotificationType.message => 'conversation',
    NotificationType.task => 'task',
    NotificationType.payment => 'payment',
    NotificationType.assignment => 'assigned client',
    NotificationType.intake ||
    NotificationType.membership ||
    NotificationType.other => 'record',
  };
}

enum NotificationDestinationFailure {
  invalidReference,
  configuration,
  unauthorized,
  forbidden,
  notFound,
  network,
  invalidData,
  server,
}

class NotificationDestinationException implements Exception {
  final NotificationDestinationFailure failure;
  final String message;

  const NotificationDestinationException(this.failure, this.message);

  bool get canRetry => switch (failure) {
    NotificationDestinationFailure.network ||
    NotificationDestinationFailure.invalidData ||
    NotificationDestinationFailure.server => true,
    _ => false,
  };

  @override
  String toString() => message;
}
