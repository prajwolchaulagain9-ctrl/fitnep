import 'dart:async';

import 'package:fitnep/core/network/backend_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'prefers local when healthy and selects Render when local is unavailable',
    () async {
      var healthy = true;
      var now = DateTime.utc(2026, 11, 24);
      final resolver = BackendResolver(
        candidates: ['http://local.test/', 'https://render.test/'],
        probe: (_) async => healthy,
        now: () => now,
      );
      addTearDown(resolver.close);
      expect(await resolver.resolve(), 'http://local.test/');
      healthy = false;
      resolver.unavailable('http://local.test/');
      expect(await resolver.resolve(), 'https://render.test/');
      healthy = true;
      now = now.add(const Duration(seconds: 16));
      expect(await resolver.resolve(), 'http://local.test/');
    },
  );

  test(
    'simultaneous API and session requests share one local health probe',
    () async {
      final pending = Completer<bool>();
      var probes = 0;
      final resolver = BackendResolver(
        candidates: ['http://local.test/', 'https://render.test/'],
        probe: (_) {
          probes++;
          return pending.future;
        },
      );
      addTearDown(resolver.close);
      final api = resolver.resolve();
      final session = resolver.resolve();
      pending.complete(true);
      expect(await api, 'http://local.test/');
      expect(await session, 'http://local.test/');
      expect(probes, 1);
    },
  );

  test('a remote-only configuration never probes localhost', () async {
    final resolver = BackendResolver(
      candidates: ['https://render.test/'],
      probe: (_) async {
        fail('A remote-only run should not probe localhost.');
      },
    );
    addTearDown(resolver.close);
    expect(await resolver.resolve(), 'https://render.test/');
  });
}
