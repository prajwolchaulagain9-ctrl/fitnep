import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes/app_router.dart';
import '../../../app/routes/app_routes.dart';
import '../../../core/services/firebase_providers.dart';
import '../data/password_recovery_service.dart';

// US 2 session revocation. Firebase remains the shared authentication state.
class PasswordResetSessionObserver extends ConsumerStatefulWidget {
  const PasswordResetSessionObserver({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PasswordResetSessionObserver> createState() =>
      _PasswordResetSessionObserverState();
}

class _PasswordResetSessionObserverState
    extends ConsumerState<PasswordResetSessionObserver>
    with WidgetsBindingObserver {
  late final PasswordRecoveryService _recovery;
  StreamSubscription<User?>? _subscription;
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _recovery = PasswordRecoveryService(ref.read(firebaseAuthProvider));
    WidgetsBinding.instance.addObserver(this);
    _subscription = _recovery.auth.authStateChanges().listen(
      (_) => _startChecking(),
      onError: (Object error) {},
    );
    _startChecking();
  }

  void _startChecking() {
    _timer?.cancel();
    final state = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        _recovery.auth.currentUser == null ||
        (state != null && state != AppLifecycleState.resumed)) {
      return;
    }
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_check()),
    );
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final ended = await _recovery.signOutIfSessionRevoked();
      if (mounted && ended && _recovery.auth.currentUser == null) {
        _timer?.cancel();
        final router = ref.read(appRouterProvider);
        final path = router.routeInformationProvider.value.uri.path;
        // Recovery stays usable while signed out; preserve reset confirmation.
        if (path != AppRoutes.forgotPasswordPath &&
            path != AppRoutes.resetPasswordPath) {
          router.goNamed(AppRoutes.welcome);
        }
      }
    } catch (_) {
      // Connection failures do not prove revocation. Retry on resume/next tick;
      // protected server operations still require revocation-aware verification.
    } finally {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startChecking();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
