import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';
import 'backend_resolver.dart';
import '../authorization/authorization_refresh.dart';
import '../../features/authentication/data/hosted_session_service.dart';
import '../../features/authentication/presentation/hosted_session_gate.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(auth: ref.watch(firebaseAuthProvider)),
);
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    resolveBackend: ref.watch(backendResolverProvider).resolve,
    backendUnavailable: ref.watch(backendResolverProvider).unavailable,
    sessionId: ref.watch(hostedSessionServiceProvider).ensure,
    prepareAccountRequest: ref.watch(hostedSessionServiceProvider).wake,
    onSessionEnded: () {
      ref.invalidate(hostedSessionReadyProvider);
      ref.read(authorizationRefreshProvider.notifier).refresh();
    },
    onPermissionDenied: () =>
        ref.read(authorizationRefreshProvider.notifier).refresh(),
  ),
);
