import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';
import '../authorization/authorization_refresh.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(auth: ref.watch(firebaseAuthProvider)),
);
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    onPermissionDenied: () =>
        ref.read(authorizationRefreshProvider.notifier).refresh(),
  ),
);
