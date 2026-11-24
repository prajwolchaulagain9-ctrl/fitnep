import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client_provider.dart';
import '../../../core/services/firebase_providers.dart';
import '../domain/account.dart';

final authorizationRepositoryProvider = Provider<AuthorizationRepository>(
  (ref) => AuthorizationRepository(
    ref.watch(apiClientProvider).dio,
    ref.watch(firestoreProvider),
  ),
);

class AuthorizationRepository {
  AuthorizationRepository(this.dio, this.firestore);
  final Dio dio;
  final FirebaseFirestore firestore;
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    if (!AppConfig.hasApiBaseUrl && dio.options.baseUrl.isEmpty) {
      throw const AuthorizationFailure(
        'FitNEP account services are not configured. Contact support.',
      );
    }
    try {
      final response = await dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(method: method),
      );
      final result = response.data;
      if (result is! Map || result['data'] is! Map) {
        throw const FormatException('Invalid account response.');
      }
      return Map<String, dynamic>.from(result['data'] as Map);
    } on DioException catch (error) {
      throw AuthorizationFailure(switch (error.response?.statusCode) {
        401 => 'Your session has ended. Please sign in again.',
        403 => 'You do not have permission to access this feature.',
        400 =>
          error.response?.data is Map
              ? (error.response!.data['error'] as String? ??
                    'Check the information and try again.')
              : 'Check the information and try again.',
        _ => 'FitNEP could not verify access. Check your connection and try again.',
      });
    }
  }

  Future<FitNepAccount> current() async => FitNepAccount.fromJson(
    Map<String, dynamic>.from((await request('session'))['account'] as Map),
  );
  Stream<FitNepAccount?> watchAccount(String uid) => firestore
      .collection('account_access')
      .doc(uid)
      .snapshots(includeMetadataChanges: true)
      .where(
        (snapshot) =>
            !snapshot.metadata.isFromCache &&
            !snapshot.metadata.hasPendingWrites,
      )
      .asyncMap((snapshot) async {
        // The document is only a notification. Authority always comes from a
        // fresh API request that verifies revocation and the current account.
        return current();
      });
  Future<void> checkPermission(String permission) async {
    await request(
      'authorization/check',
      method: 'POST',
      data: {'permission': permission},
    );
  }

  Future<List<Map<String, dynamic>>> all(
    String path,
    String key, {
    Map<String, dynamic>? query,
  }) async {
    final result = <Map<String, dynamic>>[];
    String? after;
    do {
      final page = await request(path, query: {...?query, 'after': ?after});
      result.addAll(
        (page[key] as List).map((row) => Map<String, dynamic>.from(row as Map)),
      );
      final next = page['next_cursor'] as String?;
      if (next == after && next != null) {
        throw const AuthorizationFailure('Could not load the next page.');
      }
      after = next;
    } while (after != null);
    return result;
  }
}
