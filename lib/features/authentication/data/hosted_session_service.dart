import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/config/app_config.dart';
import '../../../core/services/firebase_providers.dart';
import '../../../core/network/backend_resolver.dart';

typedef HostedIdentity = ({String uid, String token, int authTime});
typedef HostedIdentityReader = Future<HostedIdentity?> Function();

abstract interface class HostedSessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureHostedSessionStore implements HostedSessionStore {
  const SecureHostedSessionStore([this.storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String? value) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}

final hostedSessionStoreProvider = Provider<HostedSessionStore>(
  (ref) => const SecureHostedSessionStore(),
);

final hostedSessionServiceProvider = Provider<HostedSessionService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final service = HostedSessionService(
    identity: () async {
      final user = auth.currentUser;
      if (user == null) return null;
      final result = await user.getIdTokenResult();
      if (auth.currentUser?.uid != user.uid || result.token == null) {
        throw StateError('The signed-in account changed.');
      }
      return (
        uid: user.uid,
        token: result.token!,
        authTime: (result.authTime!.millisecondsSinceEpoch / 1000).floor(),
      );
    },
    store: ref.watch(hostedSessionStoreProvider),
    enabled: AppConfig.hostedSessionsEnabled,
    resolveBackend: ref.watch(backendResolverProvider).resolve,
    backendUnavailable: ref.watch(backendResolverProvider).unavailable,
    onEnded: () => auth.signOut(),
  );
  ref.onDispose(service.close);
  return service;
});

class HostedSessionService {
  HostedSessionService({
    required this.identity,
    required this.store,
    required this.enabled,
    this.onEnded,
    this.resolveBackend,
    this.backendUnavailable,
    Dio? dio,
    DateTime Function()? now,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: AppConfig.apiBaseUrl,
               connectTimeout: const Duration(seconds: 25),
               receiveTimeout: const Duration(seconds: 25),
               headers: const {'Accept': 'application/json'},
             ),
           ),
       now = now ?? DateTime.now;

  final HostedIdentityReader identity;
  final HostedSessionStore store;
  final bool enabled;
  final Future<void> Function()? onEnded;
  final Future<String> Function()? resolveBackend;
  final void Function(String)? backendUnavailable;
  final Dio dio;
  final DateTime Function() now;
  static const sessionKey = 'fitnep_hosted_session';
  static const logoutKey = 'fitnep_pending_logout';
  static const _logoutTimeout = Duration(seconds: 4);
  Future<String?>? _checking;
  DateTime? _lastHumanActivity;
  bool _reportingActivity = false;
  DateTime? _readyAt;
  Future<void>? _warming;
  int _generation = 0;

  Future<void> wake() {
    if (!enabled ||
        (_readyAt != null &&
            now().difference(_readyAt!) < const Duration(minutes: 1))) {
      return Future.value();
    }
    return _warming ??= _wake().whenComplete(() => _warming = null);
  }

  Future<void> _wake() async {
    final health = await _request('healthz', null);
    if (health['ready'] != true) {
      throw StateError('The account service is unavailable.');
    }
    _readyAt = now();
  }

  // No role is trusted from storage. /me checks current server authority.
  Future<String?> ensure() {
    if (!enabled) return Future.value(null);
    return _checking ??= _ensure().whenComplete(() => _checking = null);
  }

  Future<String?> ensureFor(String uid) async {
    if (!enabled) return null;
    if ((await identity())?.uid != uid) {
      throw StateError('The signed-in account changed.');
    }
    final id = await ensure();
    if ((await identity())?.uid != uid) {
      throw StateError('The signed-in account changed.');
    }
    return id;
  }

  Future<String?> _ensure() async {
    final actor = await identity();
    if (actor == null) throw StateError('Sign in to continue.');
    final generation = _generation;
    await reconcileLogout();
    final saved = _decode(await store.read(sessionKey));
    final matches =
        saved?['uid'] == actor.uid && saved?['auth_time'] == actor.authTime;
    final id = matches ? (saved?['session_id'] as String?) : null;
    try {
      Map<String, dynamic> view;
      String? currentId = id;
      if (id != null) {
        try {
          view = await _request('sessions/me', actor, sessionId: id);
        } on DioException catch (error) {
          if (error.response?.statusCode != 401 ||
              (error.response?.data as Map?)?['code'] !=
                  'session-authority-changed') {
            rethrow;
          }
          view = await _request('sessions/start', actor, method: 'POST');
          currentId = view['session_id'] as String?;
        }
      } else {
        view = await _request('sessions/start', actor, method: 'POST');
        currentId = view['session_id'] as String?;
      }
      final current = await identity();
      if (generation != _generation ||
          current?.uid != actor.uid ||
          current?.authTime != actor.authTime) {
        throw StateError('The signed-in account changed.');
      }
      if (view['uid'] != actor.uid ||
          view['ready'] != true ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(currentId ?? '') ||
          DateTime.tryParse(view['expires_at'] as String? ?? '') == null) {
        throw const FormatException('Invalid hosted session response.');
      }
      await store.write(
        sessionKey,
        jsonEncode({
          'uid': actor.uid,
          'auth_time': actor.authTime,
          'session_id': currentId,
        }),
      );
      return currentId;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await store.write(sessionKey, null);
        final current = await identity();
        if (generation == _generation &&
            current?.uid == actor.uid &&
            current?.authTime == actor.authTime) {
          await onEnded?.call();
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    HostedIdentity? actor, {
    String method = 'GET',
    String? sessionId,
    CancelToken? cancelToken,
  }) async {
    // Only idempotent session operations are retried for a sleeping free host.
    for (var attempt = 0; ; attempt++) {
      try {
        final baseUrl = await resolveBackend?.call();
        if (baseUrl != null) dio.options.baseUrl = baseUrl;
        final response = await dio.request<Map<String, dynamic>>(
          path,
          data: method == 'POST' ? <String, Object>{} : null,
          cancelToken: cancelToken,
          options: Options(
            method: method,
            headers: {
              if (actor != null) 'Authorization': 'Bearer ${actor.token}',
              'X-FitNEP-Session': ?sessionId,
            },
          ),
          // The same resolver also routes ApiClient's protected requests.
        );
        return Map<String, dynamic>.from(response.data?['data'] as Map? ?? {});
      } on DioException catch (error) {
        if (isBackendConnectionFailure(error)) {
          backendUnavailable?.call(error.requestOptions.baseUrl);
        }
        if (cancelToken != null ||
            attempt >= 1 ||
            error.response != null ||
            !{
              DioExceptionType.connectionTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError,
            }.contains(error.type)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> humanActivity() async {
    if (!enabled ||
        _reportingActivity ||
        (_lastHumanActivity != null &&
            now().difference(_lastHumanActivity!) <
                const Duration(minutes: 1))) {
      return;
    }
    _reportingActivity = true;
    try {
      if (await store.read(sessionKey) == null) return;
      final id = await ensure();
      final actor = await identity();
      if (id == null || actor == null) return;
      await _request('sessions/activity', actor, method: 'POST', sessionId: id);
      _lastHumanActivity = now();
    } finally {
      _reportingActivity = false;
    }
  }

  Future<void> end() async {
    _generation++;
    if (!enabled) return;
    _lastHumanActivity = null;
    final saved = _decode(await store.read(sessionKey));
    // Consent happens before an API session starts. There is nothing to revoke.
    if (saved == null) return;
    HostedIdentity? actor;
    try {
      actor = await identity().timeout(_logoutTimeout);
    } on FirebaseAuthException {
      // An unreachable token service must not prevent local sign-out.
    } on TimeoutException {
      // A stale hosted session still expires on the server.
    }
    final logoutToken =
        actor != null &&
            saved['uid'] == actor.uid &&
            saved['auth_time'] == actor.authTime
        ? actor.token
        : null;
    if (logoutToken != null) {
      // A short-lived token is retained only in encrypted pending-logout storage
      // until revocation succeeds, expires, or is rejected. It is never logged.
      await store.write(
        logoutKey,
        jsonEncode({...saved, 'token': logoutToken}),
      );
    }
    await store.write(sessionKey, null);
    if (logoutToken == null) return;
    try {
      await reconcileLogout();
    } on DioException {
      /* Reconciled on next startup. */
    }
  }

  Future<void> reconcileLogout() async {
    final pending = _decode(await store.read(logoutKey));
    if (pending == null) return;
    final cancel = CancelToken();
    final timer = Timer(_logoutTimeout, cancel.cancel);
    try {
      await _request(
        'sessions/end',
        (
          uid: pending['uid'] as String,
          token: pending['token'] as String,
          authTime: pending['auth_time'] as int,
        ),
        method: 'POST',
        sessionId: pending['session_id'] as String,
        cancelToken: cancel,
      );
    } on DioException catch (error) {
      if (![401, 403].contains(error.response?.statusCode)) rethrow;
    } finally {
      timer.cancel();
    }
    await store.write(logoutKey, null);
  }

  Future<void> rejectSession() async {
    _generation++;
    await store.write(sessionKey, null);
  }

  Map<String, dynamic>? _decode(String? value) {
    if (value == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } on FormatException {
      return null;
    }
  }

  void close() => dio.close();
}
