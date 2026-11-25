import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/authorization/authorization_refresh.dart';
import '../../authentication/presentation/controllers/authentication_controller.dart';
import '../data/authorization_repository.dart';
import '../domain/account.dart';

// Firebase Auth supplies identity; only live, server-owned accounts supply roles.
final accountSessionProvider = StreamProvider<FitNepAccount?>((ref) async* {
  await ref.watch(authenticationSettledProvider.future);
  final identity = await ref.watch(authenticationStateProvider.future);
  if (identity == null) {
    yield null;
    return;
  }
  final repository = ref.watch(authorizationRepositoryProvider);
  final initial = await repository.current();
  if (!ref.mounted) return;
  FitNepAccount? published = initial;
  final updates = StreamController<FitNepAccount?>();
  bool ended = false;
  bool hadError = false;
  void publish(FitNepAccount? account) {
    if (ended) return;
    // A denied record request must refresh authority without recreating the same
    // screen and retrying that request indefinitely when the role is unchanged.
    final changed =
        hadError ||
        published?.roleRevision != account?.roleRevision ||
        published?.id != account?.id ||
        published?.role != account?.role ||
        published?.isActive != account?.isActive ||
        (published == null) != (account == null);
    published = account;
    hadError = false;
    if (changed) {
      ref.read(authorizationEpochProvider.notifier).refresh();
      updates.add(account);
    }
  }

  final subscription = repository
      .watchAccount(identity.uid)
      .listen(
        publish,
        onError: (Object error, StackTrace trace) {
          if (!ended) {
            hadError = true;
            updates.addError(error, trace);
          }
        },
      );
  ref.listen(authorizationRefreshProvider, (_, _) async {
    try {
      publish(await repository.current());
    } catch (error, trace) {
      if (!ended) {
        hadError = true;
        updates.addError(error, trace);
      }
    }
  });
  ref.onDispose(() {
    ended = true;
    unawaited(subscription.cancel());
    unawaited(updates.close());
  });
  yield initial;
  yield* updates.stream;
}, retry: (retryCount, error) => null);
