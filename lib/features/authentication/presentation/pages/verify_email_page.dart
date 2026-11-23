import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/authentication_service.dart';
import '../../data/email_verification_service.dart';
import '../controllers/authentication_controller.dart';
import 'password_recovery_pages.dart';

class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  Timer? _timer;
  DateTime? _resendAt;
  int _remaining = 0;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _remaining = seconds;
    _resendAt = DateTime.now().add(Duration(seconds: seconds));
    _timer?.cancel();
    if (seconds == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(
        () => _remaining =
            ((_resendAt!.difference(DateTime.now()).inMilliseconds + 999) ~/
                    1000)
                .clamp(0, 3600),
      );
      if (_remaining == 0) timer.cancel();
    });
  }

  Future<void> _send({bool resend = false}) async {
    if (_busy || _remaining > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final delivery = await ref
          .read(emailVerificationServiceProvider)
          .sendCode(resend: resend);
      if (!mounted) return;
      if (delivery.emailVerified) {
        ref.invalidate(authenticationStateProvider);
        return;
      }
      _code.clear();
      setState(() {
        _sent = true;
        _startCooldown(delivery.resendAfterSeconds);
      });
    } on EmailVerificationFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          if (error.retryAfterSeconds case final int seconds) {
            _startCooldown(seconds);
          }
        });
      }
    } on AuthenticationFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn\u2019t send your code. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(emailVerificationServiceProvider).verifyCode(_code.text);
      if (!mounted) return;
      _code.clear();
      // Auth's authStateChanges does not emit on reload. Refresh the shared
      // provider so the route guard reads the updated Firebase user.
      ref.invalidate(authenticationStateProvider);
    } on AuthenticationFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'We couldn\u2019t verify your email. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authenticationStateProvider).value;
    final action = ref.watch(authenticationControllerProvider);
    final busy = _busy || action.isLoading;
    return RecoveryPage(
      title: 'Verify your email',
      description:
          'Enter the 6-digit code sent to ${user?.email ?? 'your email address'}.',
      showBackButton: false,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error ?? action.errorMessage case final String error)
              RecoveryMessage(error),
            if (_sent) ...[
              const Text('Code sent. Check your inbox and spam folder.'),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _code,
              readOnly: busy,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Verification code',
                hintText: '6-digit code',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
              validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                  ? null
                  : 'Enter the 6-digit code from your email.',
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onFieldSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : _verify,
              child: Text(_busy ? 'Please wait\u2026' : 'Verify email'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy || _remaining > 0
                  ? null
                  : () => _send(resend: _sent),
              child: Text(
                _remaining > 0
                    ? 'Resend code in ${_remaining}s'
                    : _sent
                    ? 'Resend code'
                    : 'Send code',
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => ref
                        .read(authenticationControllerProvider.notifier)
                        .signOut(),
              child: const Text('Use another account'),
            ),
          ],
        ),
      ),
    );
  }
}
