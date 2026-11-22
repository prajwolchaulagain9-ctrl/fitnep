import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return TokenStorage(auth: auth, expectedUid: auth.currentUser?.uid);
});
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(tokenStorage: ref.watch(tokenStorageProvider));
  ref.onDispose(() => client.dio.close(force: true));
  return client;
});
