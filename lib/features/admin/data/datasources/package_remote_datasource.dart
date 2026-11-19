import 'package:dio/dio.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/package_model.dart';

abstract class PackageRemoteDatasource {
  Future<List<PackageModel>> getPackages();

  Future<PackageModel> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  });
}

class PackageRemoteDatasourceImpl implements PackageRemoteDatasource {
  final ApiClient _apiClient;

  const PackageRemoteDatasourceImpl(this._apiClient);

  @override
  Future<List<PackageModel>> getPackages() async {
    _ensureConfigured();
    try {
      final response = await _apiClient.dio.get<Object?>(
        AppConstants.packagesEndpoint,
      );
      final items = _extractPackageList(response.data);
      return items.map(PackageModel.fromJson).toList(growable: false);
    } on DioException catch (error) {
      throw PackageDataException(_messageFor(error, saving: false));
    } on FormatException {
      throw const PackageDataException(
        'The package service returned invalid data.',
      );
    }
  }

  @override
  Future<PackageModel> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  }) async {
    _ensureConfigured();
    try {
      final response = await _apiClient.dio.post<Object?>(
        AppConstants.packagesEndpoint,
        data: {
          'request_id': requestId,
          'name': name,
          'duration_months': durationMonths,
          'price': price,
          'feature_description': featureDescription,
        },
      );
      return PackageModel.fromJson(_extractPackage(response.data));
    } on DioException catch (error) {
      throw PackageDataException(_messageFor(error, saving: true));
    } on FormatException {
      throw const PackageDataException(
        'The package service returned invalid data.',
      );
    }
  }

  void _ensureConfigured() {
    if (_apiClient.dio.options.baseUrl.trim().isEmpty) {
      throw const PackageDataException('Package service is not configured.');
    }
  }

  String _messageFor(DioException error, {required bool saving}) {
    final serverMessage = _extractServerMessage(error.response?.data);
    if (serverMessage != null) return serverMessage;
    switch (error.response?.statusCode) {
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return saving
            ? 'Only administrators can create packages.'
            : 'You do not have permission to view packages.';
      case 409:
        return 'This package submission conflicts with an earlier request.';
      default:
        return saving
            ? 'Unable to save the package. Check your connection and try again.'
            : 'Unable to load packages. Check your connection and try again.';
    }
  }

  List<Map<String, dynamic>> _extractPackageList(Object? responseData) {
    Object? payload = responseData;
    if (payload is Map) {
      payload = payload['data'] ?? payload;
    }
    if (payload is Map) {
      payload = payload['packages'];
    }
    if (payload is! List) {
      throw const FormatException('Expected a package list.');
    }
    return payload
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid package item.');
          }
          return Map<String, dynamic>.from(item);
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _extractPackage(Object? responseData) {
    Object? payload = responseData;
    if (payload is Map) {
      payload = payload['data'] ?? payload;
    }
    if (payload is Map) {
      payload = payload['package'] ?? payload;
    }
    if (payload is! Map) {
      throw const FormatException('Expected a package.');
    }
    return Map<String, dynamic>.from(payload);
  }

  String? _extractServerMessage(Object? responseData) {
    if (responseData is! Map) return null;
    final message = responseData['error'];
    return message is String && message.trim().isNotEmpty ? message : null;
  }
}

class PackageDataException implements Exception {
  final String message;

  const PackageDataException(this.message);

  @override
  String toString() => message;
}
