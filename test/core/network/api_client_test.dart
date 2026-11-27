import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fitnep/core/network/api_client.dart';
import 'package:fitnep/core/network/backend_resolver.dart';
import 'package:fitnep/core/storage/token_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends Fake implements User {
  _User(this.token);
  final String token;
  FirebaseAuthException? failure;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (failure != null) throw failure!;
    return token;
  }
}

class _Auth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
}

class _Adapter implements HttpClientAdapter {
  final headers = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    headers.add(Map.of(options.headers));
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'read requests recover on Render after a local connection failure',
    () async {
      final auth = _Auth()..user = _User('test-token');
      final resolver = BackendResolver(
        candidates: ['http://local.test/', 'https://render.test/'],
        probe: (_) async => true,
      );
      final adapter = _RoutingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://render.test/'))
        ..httpClientAdapter = adapter;
      final client = ApiClient(
        tokenStorage: TokenStorage(auth: auth),
        dio: dio,
        resolveBackend: resolver.resolve,
        backendUnavailable: resolver.unavailable,
      );
      addTearDown(() {
        dio.close(force: true);
        resolver.close();
      });
      await client.dio.get<void>('notifications');
      expect(adapter.hosts, ['local.test', 'render.test']);
    },
  );

  test('a failed write is not replayed, and authorization denials do not switch hosts', () async {
    final auth = _Auth()..user = _User('test-token');
    for (final status in [null, 403]) {
      final resolver = BackendResolver(
        candidates: ['http://local.test/', 'https://render.test/'],
        probe: (_) async => true,
      );
      final adapter = _RoutingAdapter(localStatus: status);
      final dio = Dio(BaseOptions(baseUrl: 'https://render.test/'))
        ..httpClientAdapter = adapter;
      final client = ApiClient(
        tokenStorage: TokenStorage(auth: auth),
        dio: dio,
        resolveBackend: resolver.resolve,
        backendUnavailable: resolver.unavailable,
      );
      await expectLater(
        status == null
            ? client.dio.post<void>('purchases', data: {'package_id': 'test'})
            : client.dio.get<void>('notifications'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.hosts, ['local.test']);
      dio.close(force: true);
      resolver.close();
    }
  });

  test(
    'a pending read stops if the user logs out before backend failover',
    () async {
      final auth = _Auth()..user = _User('first-token');
      var backend = 'http://local.test/';
      final adapter = _RoutingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final client = ApiClient(
        tokenStorage: TokenStorage(auth: auth),
        dio: dio,
        resolveBackend: () async => backend,
        backendUnavailable: (_) {
          auth.user = null;
          backend = 'https://render.test/';
        },
      );
      await expectLater(
        client.dio.get<void>('notifications'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.hosts, ['local.test']);
    },
  );

  test(
    'API reads the shared current Firebase session for every request',
    () async {
      final auth = _Auth()..user = _User('first-token');
      final adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'))
        ..httpClientAdapter = adapter;
      final client = ApiClient(
        tokenStorage: TokenStorage(auth: auth),
        dio: dio,
      );
      addTearDown(() => dio.close(force: true));
      await client.dio.get<void>('notifications');
      auth.user = _User('new-token');
      await client.dio.get<void>('notifications');
      auth.user = null;
      await client.dio.get<void>('notifications');
      expect(adapter.headers[0]['Authorization'], 'Bearer first-token');
      expect(adapter.headers[1]['Authorization'], 'Bearer new-token');
      expect(adapter.headers[2].containsKey('Authorization'), isFalse);
    },
  );

  test(
    'token refresh failure rejects the API request without sending it',
    () async {
      final auth = _Auth()
        ..user = (_User('expired')
          ..failure = FirebaseAuthException(code: 'user-token-expired'));
      final adapter = _Adapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.fitnep.test/'))
        ..httpClientAdapter = adapter;
      final client = ApiClient(
        tokenStorage: TokenStorage(auth: auth),
        dio: dio,
      );
      addTearDown(() => dio.close(force: true));
      await expectLater(
        client.dio
            .get<void>('notifications')
            .timeout(const Duration(seconds: 2)),
        throwsA(
          isA<DioException>().having(
            (error) => error.error,
            'cause',
            isA<FirebaseAuthException>(),
          ),
        ),
      );
      expect(adapter.headers, isEmpty);
    },
  );
}

class _RoutingAdapter implements HttpClientAdapter {
  _RoutingAdapter({this.localStatus});
  final int? localStatus;
  final hosts = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    hosts.add(options.uri.host);
    if (options.uri.host == 'local.test') {
      if (localStatus != null) {
        return ResponseBody.fromString('{}', localStatus!);
      }
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString('', 204);
  }

  @override
  void close({bool force = false}) {}
}
