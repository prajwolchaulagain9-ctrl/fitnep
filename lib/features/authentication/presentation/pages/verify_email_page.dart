import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../data/authentication_service.dart';
import '../../data/email_verification_service.dart';
import '../controllers/authentication_controller.dart';
import '../sign_out_to_welcome.dart';
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
  bool _usingLink = false;
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
      final service = ref.read(emailVerificationServiceProvider);
      final delivery = _usingLink
          ? await service.sendVerificationLink()
          : await service.sendCode(resend: resend);
      if (!mounted) return;
      if (delivery.emailVerified) {
        await _continueAfterVerification();
        return;
      }
      _code.clear();
      setState(() {
        _sent = true;
        _usingLink = delivery.usesVerificationLink;
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
    if (_busy || (!_usingLink && !_form.currentState!.validate())) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(emailVerificationServiceProvider);
      if (_usingLink) {
        if (!await service.checkVerificationLink()) {
          throw const AuthenticationFailure(
            'Open the verification link in your email, then try again.',
          );
        }
      } else {
        await service.verifyCode(_code.text);
      }
      if (!mounted) return;
      _code.clear();
      await _continueAfterVerification();
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

  Future<void> _continueAfterVerification() async {
    final router = GoRouter.of(context);
    final uid = ref.read(authenticationStateProvider).value?.uid;
    // Firebase's authStateChanges does not emit when the user is reloaded.
    ref.invalidate(authenticationStateProvider);
    final user = await ref.read(authenticationStateProvider.future);
    if (user != null && user.uid == uid && user.emailVerified) {
      router.goNamed(AppRoutes.appUnderDevelopment);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authenticationStateProvider).value;
    final action = ref.watch(authenticationControllerProvider);
    final busy = _busy || action.isLoading;
    final email = user?.email ?? 'your email address';
    final deliveryType = _usingLink ? 'link' : 'code';
    return RecoveryPage(
      title: 'Verify your email',
      description: _sent
          ? (_usingLink
                ? 'Open the verification link sent to $email.'
                : 'Enter the 6-digit code sent to $email.')
          : 'Verify $email to finish registration.',
      showBackButton: false,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error ?? action.errorMessage case final String error)
              RecoveryMessage(error),
            if (_sent) ...[
              const Text('Check your inbox and spam folder.'),
              const SizedBox(height: 16),
            ],
            if (!_usingLink)
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
              child: Text(
                _busy
                    ? 'Please wait\u2026'
                    : _usingLink
                    ? 'I verified my email'
                    : 'Verify email',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy || _remaining > 0
                  ? null
                  : () => _send(resend: _sent),
              child: Text(
                _remaining > 0
                    ? 'Resend $deliveryType in ${_remaining}s'
                    : _sent
                    ? 'Resend $deliveryType'
                    : 'Send verification email',
              ),
            ),
            TextButton(
              onPressed: busy ? null : () => signOutToWelcome(context, ref),
              child: const Text('Use another account'),
            ),
          ],
        ),
      ),
    );
  }
}
