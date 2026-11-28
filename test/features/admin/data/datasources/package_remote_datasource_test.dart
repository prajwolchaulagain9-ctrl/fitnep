import 'package:dio/dio.dart';
import 'package:fitnep/shared/api_client.dart';
import 'package:fitnep/shared/token_storage.dart';
import 'package:fitnep/features/admin/data/package_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads all packages from the authenticated admin endpoint', () async {
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
    expect(
      capturedRequest.uri.toString(),
      'https://api.fitnep.test/admin/packages',
    );
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

  test('loads durable package history from the admin endpoint', () async {
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
                  'history': [_historyJson],
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

    final history = await datasource.getPackageHistory();

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.uri.toString(),
      'https://api.fitnep.test/admin/package-history',
    );
    expect(history.single.adminName, 'FitNep CEO');
    expect(history.single.previousValues?['price'], 5000);
    expect(history.single.newValues['price'], 6500);
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

const _historyJson = {
  'id': 'history-1',
  'package_id': 'package-request-1',
  'package_name': 'Premium Fitness',
  'admin_id': 'admin-1',
  'admin_name': 'FitNep CEO',
  'action': 'updated',
  'previous_values': {'price': 5000},
  'new_values': {'price': 6500},
  'changed_at': '2026-11-20T04:15:00.000Z',
};
