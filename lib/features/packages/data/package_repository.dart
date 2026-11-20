import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_client_provider.dart';
import '../../../core/services/firebase_providers.dart';
import '../domain/package_models.dart';

class PackageFailure implements Exception {
  const PackageFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

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

  Future<PackageMembership> select(String packageId, String requestId) async {
    final data = await _request(
      'POST',
      '/memberships',
      body: {'package_id': packageId, 'request_id': requestId},
    );
    return PackageMembership.fromJson(
      Map<String, dynamic>.from(data['membership'] as Map),
    );
  }

  Future<List<PackageMembership>> pendingApprovals() async {
    final data = await _request('GET', '/admin/memberships/pending');
    return (data['memberships'] as List)
        .map(
          (item) => PackageMembership.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<PackageMembership> verifyPayment(
    String membershipId,
    String reference,
  ) async {
    final data = await _request(
      'POST',
      '/admin/memberships/$membershipId/verify-payment',
      body: {'reference': reference},
    );
    return PackageMembership.fromJson(
      Map<String, dynamic>.from(data['membership'] as Map),
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
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
        options: Options(method: method),
      );
      return Map<String, dynamic>.from(result.data!['data'] as Map);
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const PackageFailure(
          'Your session has ended. Please sign in again.',
        );
      }
      final data = error.response?.data;
      if (data is Map && data['error'] is String) {
        throw PackageFailure(data['error'] as String);
      }
      throw const PackageFailure(
        'We couldn’t load your packages. Check your connection and try again.',
      );
    }
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

final pendingPackageApprovalsProvider =
    FutureProvider.autoDispose<List<PackageMembership>>((ref) async {
      final repository = ref.watch(packageRepositoryProvider);
      final user = await ref.watch(packageAccountProvider.future);
      if (user == null) {
        throw const PackageFailure(
          'Sign in as an administrator to review package approvals.',
        );
      }
      return repository.pendingApprovals();
    }, retry: (count, error) => null);
