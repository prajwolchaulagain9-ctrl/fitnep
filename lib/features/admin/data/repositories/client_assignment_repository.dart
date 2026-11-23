import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_provider.dart';

const inactivePackageAssignmentMessage =
    'Only clients with an active package can be assigned.';

class AssignmentEligibility {
  const AssignmentEligibility({
    required this.canAssign,
    required this.packageStatus,
    required this.message,
  });

  final bool canAssign;
  final String packageStatus;
  final String? message;
}

class ClientAssignmentFailure implements Exception {
  const ClientAssignmentFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class ClientAssignmentRepository {
  const ClientAssignmentRepository(this._dio);
  final Dio _dio;

  Future<AssignmentEligibility> eligibility(String clientId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'admin/client-assignments/${Uri.encodeComponent(clientId)}/eligibility',
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      final eligibility = data['eligibility'] as Map<String, dynamic>;
      return AssignmentEligibility(
        canAssign: eligibility['can_assign'] as bool,
        packageStatus: eligibility['package_status'] as String,
        message: eligibility['message'] as String?,
      );
    } on DioException catch (error) {
      throw _failure(
        error,
        'Unable to verify the client package. Assignment is unavailable.',
      );
    } on TypeError {
      throw const ClientAssignmentFailure(
        'The assignment service returned invalid package information.',
      );
    }
  }

  Future<void> assign(String clientId, String dietitianId) async {
    try {
      await _dio.put<Map<String, dynamic>>(
        'admin/client-assignments/${Uri.encodeComponent(clientId)}',
        data: {'dietitian_id': dietitianId},
      );
    } on DioException catch (error) {
      throw _failure(error, 'Unable to assign this client. Try again.');
    }
  }

  ClientAssignmentFailure _failure(DioException error, String fallback) {
    final response = error.response;
    final data = response?.data;
    if (data is Map<String, dynamic> &&
        data['error'] is String &&
        const {400, 403, 404, 409, 503}.contains(response?.statusCode)) {
      return ClientAssignmentFailure(data['error'] as String);
    }
    return ClientAssignmentFailure(
      response?.statusCode == 401
          ? 'Your session ended. Sign in again.'
          : fallback,
    );
  }
}

final clientAssignmentRepositoryProvider = Provider<ClientAssignmentRepository>(
  (ref) => ClientAssignmentRepository(ref.watch(apiClientProvider).dio),
);
