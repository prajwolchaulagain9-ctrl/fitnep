import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hosted_session_service.dart';

final hostedSessionReadyProvider = FutureProvider.autoDispose
    .family<String?, String>(
      (ref, uid) => ref.watch(hostedSessionServiceProvider).ensureFor(uid),
      retry: (count, error) => null,
    );

class HostedSessionGate extends ConsumerWidget {
  const HostedSessionGate({super.key, required this.uid, required this.child});
  final String uid;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(hostedSessionReadyProvider(uid))
      .when(
        skipLoadingOnRefresh: false,
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'FitNEP could not confirm your session. Check your connection and try again.',
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(hostedSessionReadyProvider(uid)),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (_) => child,
      );
}

// Polling and lifecycle resume only verify. Taps/keyboard input report activity.
class HostedSessionObserver extends ConsumerStatefulWidget {
  const HostedSessionObserver({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<HostedSessionObserver> createState() =>
      _HostedSessionObserverState();
}

class _HostedSessionObserverState extends ConsumerState<HostedSessionObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _activity() {
    final service = ref.read(hostedSessionServiceProvider);
    // Visible requests/guards report errors. A gesture never exposes data itself.
    unawaited(service.humanActivity().catchError((Object _) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(hostedSessionReadyProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _activity(),
    child: Focus(
      onKeyEvent: (_, _) {
        _activity();
        return KeyEventResult.ignored;
      },
      child: widget.child,
    ),
  );
}
