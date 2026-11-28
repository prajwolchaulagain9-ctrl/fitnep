import 'package:dio/dio.dart';

import '../../../shared/app_constants.dart';
import '../../../shared/api_client.dart';
import 'package_purchase_model.dart';

abstract class PackagePurchaseRemoteDatasource {
  Future<PackagePurchaseModel?> getCurrentPurchase();

  Future<PackagePurchaseModel> purchasePackage({
    required String packageId,
    required String requestId,
  });
}

class PackagePurchaseRemoteDatasourceImpl
    implements PackagePurchaseRemoteDatasource {
  final ApiClient _apiClient;

  const PackagePurchaseRemoteDatasourceImpl(this._apiClient);

  @override
  Future<PackagePurchaseModel?> getCurrentPurchase() async {
    _ensureConfigured();
    try {
      final response = await _apiClient.dio.get<Object?>(
        AppConstants.currentPurchaseEndpoint,
      );
      final purchase = _extractPurchase(response.data, allowNull: true);
      return purchase == null ? null : PackagePurchaseModel.fromJson(purchase);
    } on DioException catch (error) {
      throw PackagePurchaseDataException(_messageFor(error));
    } on FormatException {
      throw const PackagePurchaseDataException(
        'The membership service returned invalid data.',
      );
    }
  }

  @override
  Future<PackagePurchaseModel> purchasePackage({
    required String packageId,
    required String requestId,
  }) async {
    _ensureConfigured();
    try {
      final response = await _apiClient.dio.post<Object?>(
        AppConstants.purchasesEndpoint,
        data: {'package_id': packageId, 'request_id': requestId},
      );
      final purchase = _extractPurchase(response.data, allowNull: false);
      if (purchase == null) throw const FormatException('Missing purchase.');
      return PackagePurchaseModel.fromJson(purchase);
    } on DioException catch (error) {
      throw PackagePurchaseDataException(_messageFor(error));
    } on FormatException {
      throw const PackagePurchaseDataException(
        'The membership service returned invalid data.',
      );
    }
  }

  Map<String, dynamic>? _extractPurchase(
    Object? responseData, {
    required bool allowNull,
  }) {
    Object? payload = responseData;
    if (payload is Map) payload = payload['data'] ?? payload;
    if (payload is Map) payload = payload['purchase'];
    if (payload == null && allowNull) return null;
    if (payload is! Map) throw const FormatException('Expected a purchase.');
    return Map<String, dynamic>.from(payload);
  }

  void _ensureConfigured() {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw const PackagePurchaseDataException(
        'Membership service is not configured.',
      );
    }
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      final message = (data['error'] as String).trim();
      if (message.isNotEmpty) return message;
    }
    if (error.response?.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    if (error.response?.statusCode == 404) {
      return 'This package is no longer available.';
    }
    return 'Unable to update your membership. Check your connection and try again.';
  }
}

class PackagePurchaseDataException implements Exception {
  final String message;

  const PackagePurchaseDataException(this.message);

  @override
  String toString() => message;
}
