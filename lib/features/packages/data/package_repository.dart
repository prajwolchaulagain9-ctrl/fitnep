import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/api_client.dart';
import '../../../shared/api_client_provider.dart';
import '../../../shared/authorization_refresh.dart';
import '../../../shared/firebase_providers.dart';
import 'package_models.dart';
import 'payment_models.dart';

class PackageFailure implements Exception {
  const PackageFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String newPackageRequestId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 31)}';

class PackageRepository {
  PackageRepository(this.api);
  final ApiClient api;

  Future<List<PackageOption>> catalog() async {
    final data = await _request('GET', '/packages');
    return (data['packages'] as List)
        .map(
          (item) =>
              PackageOption.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<List<PackageMembership>> memberships() async {
    final data = await _request('GET', '/memberships/me');
    return (data['memberships'] as List)
        .map(
          (item) => PackageMembership.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<PackageMembership> select(
    String packageId,
    String requestId, {
    String? clientId,
  }) async {
    final data = await _request(
      'POST',
      '/memberships',
      body: {
        'package_id': packageId,
        'request_id': requestId,
        'expected_client_id': ?clientId,
      },
    );
    return PackageMembership.fromJson(
      Map<String, dynamic>.from(data['membership'] as Map),
    );
  }

  Future<PackageCheckout?> checkout() async {
    final data = await _request('GET', '/payments/checkout');
    final checkout = data['checkout'] as Map<String, dynamic>?;
    return checkout == null ? null : PackageCheckout.fromJson(checkout);
  }

  Future<PackagePayment> submitProof({
    required String membershipId,
    required String clientId,
    required String reference,
    required String requestId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final data = await _request(
      'POST',
      '/payments/${Uri.encodeComponent(membershipId)}/proof',
      body: {
        'proof_base64': base64Encode(bytes),
        'content_type': contentType,
        'request_id': requestId,
        'expected_client_id': clientId,
        'expected_reference': reference,
      },
    );
    return PackagePayment.fromJson(data['payment'] as Map<String, dynamic>);
  }

  Future<List<PackagePayment>> paymentHistory() => _payments('/payments/me');

  Future<List<PackagePayment>> reviewQueue(PaymentStatus status) =>
      _payments('/admin/payments', query: {'status': status.name});

  Future<List<PackagePayment>> _payments(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final data = await _request('GET', path, query: query);
    return (data['payments'] as List)
        .map((item) => PackagePayment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<PaymentDetails?> paymentDetails(String id) async {
    final data = await _request('GET', '/payments/${Uri.encodeComponent(id)}');
    final payment = data['payment'] as Map<String, dynamic>? ?? data;
    if (!payment.containsKey('qr_payload') &&
        !data.containsKey('adjustments')) {
      return null; // Existing payment notifications can point to legacy records.
    }
    return (
      payment: PackagePayment.fromJson(payment),
      adjustments: (data['adjustments'] as List? ?? const [])
          .map(
            (item) => PaymentAdjustment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  Future<Uint8List> paymentProof(String id) async {
    try {
      final response = await api.dio.get<List<int>>(
        '/payments/${Uri.encodeComponent(id)}/proof',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const PackageFailure('The proof image could not be loaded.');
      }
      return Uint8List.fromList(data);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  Future<PackagePayment> reviewPayment(
    PackagePayment payment, {
    String? reason,
  }) async {
    final action = reason == null ? 'verify' : 'reject';
    final data = await _request(
      'POST',
      '/admin/payments/${Uri.encodeComponent(payment.id)}/$action',
      body: {
        'revision': ?payment.revision,
        'reason': ?reason,
        if (reason == null) 'proof_reviewed': true,
      },
    );
    return PackagePayment.fromJson(data['payment'] as Map<String, dynamic>);
  }

  Future<void> addAdjustment({
    required String paymentId,
    required String reason,
    required num amountDeltaNpr,
    required String requestId,
  }) async {
    await _request(
      'POST',
      '/admin/payments/${Uri.encodeComponent(paymentId)}/adjustments',
      body: {
        'reason': reason,
        'amount_delta_npr': amountDeltaNpr,
        'request_id': requestId,
      },
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
  }) async {
    if (api.dio.options.baseUrl.trim().isEmpty) {
      throw const PackageFailure(
        'Package service is not connected yet. Please try again once it is available.',
      );
    }
    try {
      final result = await api.dio.request<Map<String, dynamic>>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method),
      );
      return Map<String, dynamic>.from(result.data!['data'] as Map);
    } on DioException catch (error) {
      throw _failure(error);
    }
  }

  PackageFailure _failure(DioException error) {
    if (error.response?.statusCode == 401) {
      return const PackageFailure(
        'Your session has ended. Please sign in again.',
      );
    }
    final data = error.response?.data;
    if (data is Map && data['error'] is String) {
      return PackageFailure(data['error'] as String);
    }
    return const PackageFailure(
      'We couldn’t reach the package and payment service. Try again.',
    );
  }
}

final packageRepositoryProvider = Provider<PackageRepository>(
  (ref) => PackageRepository(ref.watch(apiClientProvider)),
);
final packageAccountProvider = StreamProvider.autoDispose<User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);
final availablePackagesProvider =
    FutureProvider.autoDispose<List<PackageOption>>((ref) async {
      final user = await ref.watch(packageAccountProvider.future);
      if (user == null) {
        throw const PackageFailure('Sign in to view available packages.');
      }
      return ref.watch(packageRepositoryProvider).catalog();
    }, retry: (count, error) => null);
final packageMembershipsProvider =
    FutureProvider.autoDispose<List<PackageMembership>>((ref) async {
      final user = await ref.watch(packageAccountProvider.future);
      if (user == null) {
        throw const PackageFailure('Sign in to view your membership.');
      }
      return ref.watch(packageRepositoryProvider).memberships();
    }, retry: (count, error) => null);

Future<PackageRepository> _signedInRepository(Ref ref) async {
  ref.watch(authorizationEpochProvider);
  final repository = ref.watch(packageRepositoryProvider);
  final user = await ref.watch(packageAccountProvider.future);
  if (user == null) {
    throw const PackageFailure('Sign in to access your payments.');
  }
  return repository;
}

final paymentCheckoutProvider = FutureProvider.autoDispose<PackageCheckout?>(
  (ref) async => (await _signedInRepository(ref)).checkout(),
  retry: (count, error) => null,
);
final paymentHistoryProvider = FutureProvider.autoDispose<List<PackagePayment>>(
  (ref) async => (await _signedInRepository(ref)).paymentHistory(),
  retry: (count, error) => null,
);
final paymentReviewQueueProvider = FutureProvider.autoDispose
    .family<List<PackagePayment>, PaymentStatus>(
      (ref, status) async =>
          (await _signedInRepository(ref)).reviewQueue(status),
      retry: (count, error) => null,
    );
final paymentDetailsProvider = FutureProvider.autoDispose
    .family<PaymentDetails?, String>(
      (ref, id) async => (await _signedInRepository(ref)).paymentDetails(id),
      retry: (count, error) => null,
    );
final paymentProofProvider = FutureProvider.autoDispose
    .family<Uint8List, String>(
      (ref, id) async => (await _signedInRepository(ref)).paymentProof(id),
      retry: (count, error) => null,
    );
