import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_providers.dart';
import '../storage/token_storage.dart';
import 'api_client.dart';

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(auth: ref.watch(firebaseAuthProvider)),
);
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(tokenStorage: ref.watch(tokenStorageProvider)),
);
