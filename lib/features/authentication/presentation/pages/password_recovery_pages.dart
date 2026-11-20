import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/fitnep_wordmark.dart';
import '../../data/password_recovery_service.dart';

// Shared authentication layout, based on the supplied recovery screenshots.
class RecoveryPage extends StatelessWidget {
  const RecoveryPage({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.showBackButton = true,
  });

  final String title;
  final String description;
  final Widget child;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF6B00),
      brightness: Brightness.light,
    ).copyWith(primary: const Color(0xFFFF6B00), onPrimary: Colors.white);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return Theme(
      data: base.copyWith(
        scaffoldBackgroundColor: Colors.white,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            shape: const StadiumBorder(),
            textStyle: base.textTheme.labelLarge?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: AppPage(
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBackButton) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.goNamed(AppRoutes.welcome);
                      }
                    },
                    icon: const Icon(Icons.arrow_back, size: 20),
                    label: const Text('Back'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Center(child: FitNepWordmark()),
              const SizedBox(height: 32),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF102637),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Color(0xFF657A8C),
                ),
              ),
              const SizedBox(height: 24),
              child,
              const SizedBox(height: 40),
              const Text(
                'Move better. Feel stronger. Live healthier.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF657A8C)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecoveryMessage extends StatelessWidget {
  const RecoveryMessage(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          height: 1.5,
        ),
      ),
    ),
  );
}

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passwordRecoveryProvider).request(_email.text);
      if (mounted) setState(() => _sent = true);
    } on RecoveryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn’t send your request. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RecoveryPage(
    title: _sent ? 'Check your email' : 'Forgot password?',
    description: _sent ? PasswordRecoveryService.requestConfirmation : 'Enter your registered email address to get a secure password reset link.',
    child: _sent
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => context.pushNamed(AppRoutes.resetPassword),
                child: const Text('Use a reset link'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() {
                  _sent = false;
                  _email.clear();
                }),
                child: const Text('Try another email'),
              ),
            ],
          )
        : Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) RecoveryMessage(_error!),
                TextFormField(
                  controller: _email,
                  readOnly: _busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: PasswordRecoveryService.emailError,
                  onFieldSubmitted: (_) => _send(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(_busy ? 'Sending…' : 'Send reset link'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.pushNamed(AppRoutes.resetPassword),
                  child: const Text('Already have a reset link?'),
                ),
              ],
            ),
          ),
  );
}

class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key, this.initialLink});
  final String? initialLink;

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  String? _code;
  String? _error;
  bool _busy = false;
  bool _invalidLink = false;
  bool _complete = false;
  bool _needsSignOut = false;

  @override
  void initState() {
    super.initState();
    final link = widget.initialLink;
    if (link != null) {
      _link.text = link;
      Future.microtask(_verify);
    }
  }

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!mounted || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _invalidLink = false;
    });
    try {
      final code = PasswordRecoveryService.actionCode(_link.text);
      await ref.read(passwordRecoveryProvider).verify(code);
      if (mounted) {
        setState(() {
          _code = code;
          _link.clear();
        });
      }
    } on RecoveryFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _invalidLink = error.invalidLink;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn’t verify your link. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passwordRecoveryProvider).confirm(_code!, _password.text);
      if (!mounted) return;
      _clearSecrets();
      if (mounted) setState(() => _complete = true);
    } on RecoveryFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _invalidLink = error.invalidLink;
          if (error.passwordUpdated) {
            _clearSecrets();
            _complete = true;
            _needsSignOut = true;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'We couldn’t reset your password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearSecrets() {
    _password.clear();
    _confirmation.clear();
    _link.clear();
    _code = null;
  }

  Future<void> _finishSignOut() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passwordRecoveryProvider).clearLocalSession();
      if (mounted) setState(() => _needsSignOut = false);
    } on RecoveryFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RecoveryPage(
    title: _complete
        ? 'Password updated'
        : _code == null
        ? 'Use your reset link'
        : 'Create a new password',
    description: _complete
        ? 'Sign in again with your new password.'
        : _code == null
        ? 'Copy the password reset link from your email and paste it below.'
        : 'Choose a unique password that meets your account security requirements.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) RecoveryMessage(_error!),
        if (_complete)
          FilledButton(
            onPressed: _busy
                ? null
                : _needsSignOut
                ? _finishSignOut
                : () => context.goNamed(AppRoutes.login),
            child: Text(
              _busy
                  ? 'Signing out…'
                  : _needsSignOut
                  ? 'Finish signing out'
                  : 'Back to login',
            ),
          )
        else if (_invalidLink)
          FilledButton(
            onPressed: () => context.goNamed(AppRoutes.forgotPassword),
            child: const Text('Request a new reset link'),
          )
        else if (_code == null) ...[
          TextField(
            controller: _link,
            readOnly: _busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Reset link or code',
              prefixIcon: Icon(Icons.link),
            ),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: Text(_busy ? 'Checking…' : 'Continue'),
          ),
        ] else
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RecoveryPasswordField(
                  controller: _password,
                  label: 'New password',
                  enabled: !_busy,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your new password.'
                      : null,
                ),
                const SizedBox(height: 16),
                RecoveryPasswordField(
                  controller: _confirmation,
                  label: 'Confirm new password',
                  enabled: !_busy,
                  validator: (value) => value != _password.text
                      ? 'Your passwords do not match.'
                      : null,
                  onSubmitted: (_) => _reset(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _reset,
                  child: Text(_busy ? 'Updating…' : 'Update password'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class RecoveryPasswordField extends StatefulWidget {
  const RecoveryPasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    required this.enabled,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<RecoveryPasswordField> createState() => _RecoveryPasswordFieldState();
}

class _RecoveryPasswordFieldState extends State<RecoveryPasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    readOnly: !widget.enabled,
    obscureText: _hidden,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: widget.onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    decoration: InputDecoration(
      labelText: widget.label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: _hidden
            ? 'Show ${widget.label.toLowerCase()}'
            : 'Hide ${widget.label.toLowerCase()}',
        onPressed: widget.enabled
            ? () => setState(() => _hidden = !_hidden)
            : null,
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
  );
}
