import 'package:cloud_functions/cloud_functions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/api_client_provider.dart';

typedef HostedAuthRequest = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, Object> data,
);

final hostedAuthRequestProvider = Provider<HostedAuthRequest>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return (path, data) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(path, data: data);
      return Map<String, dynamic>.from(response.data?['data'] as Map? ?? {});
    } on DioException catch (error) {
      final body = error.response?.data;
      throw FirebaseFunctionsException(
        code: body is Map && body['code'] is String
            ? body['code'] as String
            : error.response?.statusCode == 404
            ? 'unimplemented'
            : 'unavailable',
        message: 'The account service could not complete the request.',
        details: body is Map ? body['details'] : null,
      );
    }
  };
});
