import 'package:fitnep/features/authentication/data/hosted_session_service.dart';

// Widget fixtures replace network sessions explicitly; the app defaults to Render.
final offlineHostedSessionOverride = hostedSessionServiceProvider.overrideWith((
  ref,
) {
  final service = HostedSessionService(
    identity: () async => null,
    store: _Store(),
    enabled: false,
  );
  ref.onDispose(service.close);
  return service;
});

class _Store implements HostedSessionStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String? value) async {}
}
