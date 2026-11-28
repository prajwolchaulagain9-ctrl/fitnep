import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fitnep/features/authentication/data/hosted_session_service.dart';
import 'package:fitnep/shared/backend_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store implements HostedSessionStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int meStatus = 200;
  String? meCode;
  bool offlineLogout = false;
  bool failLocal = false;
  void Function()? beforeResponse;
  final id = 'a' * 43;
  final rotated = 'b' * 43;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (failLocal && options.uri.host == 'local.test') {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    beforeResponse?.call();
    final path = options.path;
    if (path == 'sessions/end' && offlineLogout) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
      );
    }
    if (path == 'sessions/me' && meStatus != 200) {
      return ResponseBody.fromString(
        jsonEncode({'code': meCode}),
        meStatus,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'uid': 'client-a',
          'role': 'client',
          'ready': true,
          'expires_at': '2026-11-22T12:00:00Z',
          if (path == 'sessions/start')
            'session_id': meCode == 'session-authority-changed' ? rotated : id,
        },
      }),
      path == 'sessions/end' ? 204 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Store store;
  late _Adapter adapter;
  late HostedSessionService service;
  HostedIdentity? actor;
  var ended = 0;
  var identityReads = 0;
  DateTime clock = DateTime.utc(2026, 11, 22);
  setUp(() {
    store = _Store();
    adapter = _Adapter();
    ended = 0;
    identityReads = 0;
    actor = (uid: 'client-a', token: 'synthetic-token', authTime: 1234);
    clock = DateTime.utc(2026, 11, 22);
    final dio = Dio(BaseOptions(baseUrl: 'https://fitnep.test/'))
      ..httpClientAdapter = adapter;
    service = HostedSessionService(
      identity: () async {
        identityReads++;
        return actor;
      },
      store: store,
      enabled: true,
      dio: dio,
      now: () => clock,
      onEnded: () async {
        ended++;
        actor = null;
      },
    );
  });
  tearDown(() => service.close());
  test(
    'hosted sessions use the same local-to-Render resolution as API requests',
    () async {
      final resolver = BackendResolver(
        candidates: ['http://local.test/', 'https://render.test/'],
        probe: (_) async => true,
      );
      adapter.failLocal = true;
      final routed = HostedSessionService(
        identity: () async => actor,
        store: store,
        enabled: true,
        dio: Dio()..httpClientAdapter = adapter,
        now: () => clock,
        resolveBackend: resolver.resolve,
        backendUnavailable: resolver.unavailable,
      );
      addTearDown(() {
        routed.close();
        resolver.close();
      });
      expect(await routed.ensure(), adapter.id);
      expect(adapter.requests.map((request) => request.uri.host), [
        'local.test',
        'render.test',
      ]);
      expect(await resolver.resolve(), 'https://render.test/');
    },
  );

  test('start stores opaque credentials without caching authority', () async {
    expect(await service.ensure(), adapter.id);
    final saved =
        jsonDecode(store.values[HostedSessionService.sessionKey]!) as Map;
    expect(saved['uid'], 'client-a');
    expect(saved.containsKey('role'), isFalse);
    expect(saved.containsKey('token'), isFalse);
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer synthetic-token',
    );
  });
  test(
    'restoration verifies persisted session without starting or renewing it',
    () async {
      await service.ensure();
      adapter.requests.clear();
      expect(await service.ensure(), adapter.id);
      expect(adapter.requests.map((r) => r.path), ['sessions/me']);
      expect(adapter.requests.single.headers['X-FitNEP-Session'], adapter.id);
    },
  );
  test(
    'a removed authority snapshot rotates only on the explicit server code',
    () async {
      await service.ensure();
      adapter.requests.clear();
      adapter.meStatus = 401;
      adapter.meCode = 'session-authority-changed';
      expect(await service.ensure(), adapter.rotated);
      expect(adapter.requests.map((r) => r.path), [
        'sessions/me',
        'sessions/start',
      ]);
      expect(ended, 0);
    },
  );
  test(
    'closed or expired sessions cannot reopen using the captured token',
    () async {
      await service.ensure();
      adapter.requests.clear();
      adapter.meStatus = 401;
      await expectLater(service.ensure(), throwsA(isA<DioException>()));
      expect(adapter.requests.map((r) => r.path), ['sessions/me']);
      expect(ended, 1);
      expect(
        store.values.containsKey(HostedSessionService.sessionKey),
        isFalse,
      );
    },
  );
  test('concurrent restoration checks share one handshake', () async {
    await Future.wait([service.ensure(), service.ensure(), service.ensure()]);
    expect(adapter.requests, hasLength(1));
  });
  test(
    'a route cannot attach a session belonging to a different UID',
    () async {
      await expectLater(service.ensureFor('client-b'), throwsStateError);
      expect(adapter.requests, isEmpty);
    },
  );
  test(
    'cold-start health checks are shared and never report activity',
    () async {
      await Future.wait([service.wake(), service.wake(), service.wake()]);
      await service.wake();
      expect(adapter.requests.map((r) => r.path), ['healthz']);
      expect(
        adapter.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    },
  );
  test(
    'account switching during a response cannot persist the previous session',
    () async {
      adapter.beforeResponse = () {
        actor = (uid: 'client-b', token: 'different-token', authTime: 1235);
      };
      await expectLater(service.ensure(), throwsStateError);
      expect(
        store.values.containsKey(HostedSessionService.sessionKey),
        isFalse,
      );
    },
  );
  test(
    'polling never reports human activity; gestures are throttled',
    () async {
      await service.ensure();
      await service.ensure();
      expect(
        adapter.requests.where((r) => r.path == 'sessions/activity'),
        isEmpty,
      );
      await service.humanActivity();
      await service.humanActivity();
      expect(
        adapter.requests.where((r) => r.path == 'sessions/activity'),
        hasLength(1),
      );
      clock = clock.add(const Duration(minutes: 1));
      await service.humanActivity();
      expect(
        adapter.requests.where((r) => r.path == 'sessions/activity'),
        hasLength(2),
      );
    },
  );
  test(
    'signing out before a hosted session starts skips the token and network',
    () async {
      await service.end();
      expect(identityReads, 0);
      expect(adapter.requests, isEmpty);
    },
  );

  test('offline logout clears the session and reconciles once connectivity returns', () async {
    await service.ensure();
    adapter.offlineLogout = true;
    await service.end();
    expect(store.values.containsKey(HostedSessionService.sessionKey), isFalse);
    expect(store.values.containsKey(HostedSessionService.logoutKey), isTrue);
    actor = null;
    adapter.offlineLogout = false;
    await service.reconcileLogout();
    expect(store.values.containsKey(HostedSessionService.logoutKey), isFalse);
    expect(adapter.requests.last.headers['X-FitNEP-Session'], adapter.id);
  });
}
