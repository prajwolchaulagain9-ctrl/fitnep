import 'package:dio/dio.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/admin/data/datasources/package_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads packages from the authenticated package endpoint', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': {
                  'packages': [_packageJson],
                },
              },
            ),
          );
        },
      ),
    );
    final datasource = PackageRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    final packages = await datasource.getPackages();

    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.uri.toString(), 'https://api.fitnep.test/packages');
    expect(packages.single.name, 'Premium Fitness');
  });

  test('posts every package field and request id to the API', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 201,
              data: {
                'data': {'package': _packageJson},
              },
            ),
          );
        },
      ),
    );
    final datasource = PackageRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    final created = await datasource.createPackage(
      requestId: 'package-request-1',
      name: 'Premium Fitness',
      durationMonths: 3,
      price: 2500,
      featureDescription: 'Personal training and nutrition guidance.',
    );

    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.uri.toString(), 'https://api.fitnep.test/packages');
    expect(capturedRequest.data, {
      'request_id': 'package-request-1',
      'name': 'Premium Fitness',
      'duration_months': 3,
      'price': 2500.0,
      'feature_description': 'Personal training and nutrition guidance.',
    });
    expect(created.id, 'package-request-1');
  });
}

const _packageJson = {
  'id': 'package-request-1',
  'name': 'Premium Fitness',
  'duration_months': 3,
  'price': 2500,
  'feature_description': 'Personal training and nutrition guidance.',
  'created_at': '2026-11-19T12:00:00.000Z',
};
