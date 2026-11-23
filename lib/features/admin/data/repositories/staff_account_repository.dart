import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/services/firebase_providers.dart';
import '../../../../core/storage/token_storage.dart';
import '../../domain/entities/staff_account_entity.dart';

final staffAccountRepositoryProvider = Provider.autoDispose
    .family<StaffAccountRepository, String>((ref, uid) {
      final api = ApiClient(
        tokenStorage: TokenStorage(
          auth: ref.watch(firebaseAuthProvider),
          expectedUid: uid,
        ),
      );
      ref.onDispose(() => api.dio.close(force: true));
      return StaffAccountRepository(api.dio);
    });

class StaffAccountRepository {
  const StaffAccountRepository(this._dio);

  static const _accounts = 'admin/staff-accounts';
  final Dio _dio;

  Future<StaffPage<StaffAccount>> list(String? cursor) async {
    final seenCursors = <String?>{cursor};
    do {
      final page = await _page(_accounts, 'accounts', cursor, _account);
      if (page.items.isNotEmpty || page.nextCursor == null) return page;
      cursor = page.nextCursor;
    } while (seenCursors.add(cursor));
    throw const StaffAccountFailure(
      'Could not load staff accounts. Try again.',
    );
  }

  Future<StaffPage<StaffAccountHistoryEntry>> history(String? cursor) =>
      _page('$_accounts/history', 'entries', cursor, _historyEntry);

  Future<void> create(String requestId, Map<String, String> fields) async {
    await _save('POST', _accounts, requestId, fields);
  }

  Future<void> update(
    String uid,
    String requestId,
    Map<String, String> fields,
  ) async {
    await _save(
      'PATCH',
      '$_accounts/${Uri.encodeComponent(uid)}',
      requestId,
      fields,
    );
  }

  Future<StaffAccount> setActive(
    String uid,
    String requestId,
    bool isActive,
  ) async {
    final result = await _save(
      'PATCH',
      '$_accounts/${Uri.encodeComponent(uid)}/active',
      requestId,
      {'is_active': isActive},
    );
    try {
      final data = result.data!['data'] as Map<String, dynamic>;
      return _account(data['account'] as Map<String, dynamic>);
    } on TypeError {
      throw const StaffAccountFailure(
        'Could not confirm the account status. Try again.',
      );
    }
  }

  Future<StaffPage<T>> _page<T>(
    String path,
    String key,
    String? cursor,
    T Function(Map<String, dynamic>) parse,
  ) async {
    _checkConfiguration();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {'cursor': ?cursor},
      );
      final data = response.data!['data'] as Map<String, dynamic>;
      final entries = (data[key] as List<dynamic>).cast<Map<String, dynamic>>();
      final nextCursor = data['next_cursor'] as String?;
      if (cursor != null && nextCursor == cursor) {
        throw const FormatException('The cursor did not advance.');
      }
      return (items: entries.map(parse).toList(), nextCursor: nextCursor);
    } on DioException catch (error) {
      throw _failure(error, 'Could not load staff records. Try again.');
    } on FormatException {
      throw const StaffAccountFailure(
        'The staff service returned invalid data.',
      );
    } on TypeError {
      throw const StaffAccountFailure(
        'The staff service returned invalid data.',
      );
    }
  }

  Future<Response<Map<String, dynamic>>> _save(
    String method,
    String path,
    String requestId,
    Map<String, Object> fields,
  ) async {
    _checkConfiguration();
    try {
      return await _dio.request<Map<String, dynamic>>(
        path,
        data: {...fields, 'request_id': requestId},
        options: Options(method: method),
      );
    } on DioException catch (error) {
      throw _failure(error, 'Could not confirm the change. Try again.');
    }
  }

  void _checkConfiguration() {
    if (!AppConfig.hasApiBaseUrl && _dio.options.baseUrl.isEmpty) {
      throw const StaffAccountFailure(
        'The staff account service is unavailable.',
      );
    }
  }

  StaffAccountFailure _failure(DioException error, String fallback) {
    final response = error.response;
    final data = response?.data;
    if (data is Map<String, dynamic> &&
        data['error'] is String &&
        const {400, 403, 404, 409, 503}.contains(response?.statusCode)) {
      return StaffAccountFailure(data['error'] as String);
    }
    return StaffAccountFailure(
      response?.statusCode == 401
          ? 'Your session ended. Sign in again.'
          : fallback,
    );
  }
}

class StaffAccountFailure implements Exception {
  const StaffAccountFailure(this.message);
  final String message;
}

StaffAccount _account(Map<String, dynamic> json) => StaffAccount(
  uid: json['uid'] as String,
  name: json['name'] as String?,
  email: json['email'] as String?,
  role: StaffRole.values.byName(json['role'] as String),
  isActive: json['is_active'] as bool,
);

StaffAccountHistoryEntry _historyEntry(Map<String, dynamic> json) {
  final before = json['before'] as Map<String, dynamic>?;
  final action = json['action'] as String;
  return StaffAccountHistoryEntry(
    action: StaffAccountAction.values.byName(
      action == 'role_changed' ? 'roleChanged' : action,
    ),
    actor: (json['actor_name'] ?? json['actor_uid']) as String,
    before: before == null ? null : _account(before),
    after: _account(json['after'] as Map<String, dynamic>),
    completedAt: DateTime.parse(json['completed_at'] as String),
  );
}
