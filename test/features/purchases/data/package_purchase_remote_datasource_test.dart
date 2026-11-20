import 'package:dio/dio.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:fitnep/features/purchases/data/datasources/package_purchase_remote_datasource.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creates a purchase and sends only package and idempotency ids',
    () async {
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
                  'data': {'purchase': _purchaseJson},
                },
              ),
            );
          },
        ),
      );
      final datasource = PackagePurchaseRemoteDatasourceImpl(
        ApiClient(tokenStorage: const TokenStorage(), dio: dio),
      );

      final purchase = await datasource.purchasePackage(
        packageId: 'premium',
        requestId: 'purchase-request-1',
      );

      expect(capturedRequest.method, 'POST');
      expect(
        capturedRequest.uri.toString(),
        'https://api.fitnep.test/purchases',
      );
      expect(capturedRequest.data, {
        'package_id': 'premium',
        'request_id': 'purchase-request-1',
      });
      expect(purchase.pricePaid, 5000);
    },
  );

  test('loads membership terms from the purchase snapshot endpoint', () async {
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
                'data': {'purchase': _purchaseJson},
              },
            ),
          );
        },
      ),
    );
    final datasource = PackagePurchaseRemoteDatasourceImpl(
      ApiClient(tokenStorage: const TokenStorage(), dio: dio),
    );

    final purchase = await datasource.getCurrentPurchase();

    expect(capturedRequest.method, 'GET');
    expect(
      capturedRequest.uri.toString(),
      'https://api.fitnep.test/purchases/current',
    );
    expect(purchase?.featureDescription, _purchaseJson['feature_description']);
  });
}

const _purchaseJson = {
  'id': 'purchase-1',
  'package_id': 'premium',
  'package_name': 'Premium',
  'price_paid': 5000,
  'duration_months': 3,
  'feature_description': 'Diet Plan, Workout Plan, Weekly Consultation',
  'purchased_at': '2026-01-31T12:00:00.000Z',
  'expires_at': '2026-04-30T12:00:00.000Z',
};
