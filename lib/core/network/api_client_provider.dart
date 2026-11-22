import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';
import '../authorization/authorization_refresh.dart';
import '../../features/authentication/data/hosted_session_service.dart';
import '../../features/authentication/presentation/hosted_session_gate.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(auth: ref.watch(firebaseAuthProvider)),
);
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
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
