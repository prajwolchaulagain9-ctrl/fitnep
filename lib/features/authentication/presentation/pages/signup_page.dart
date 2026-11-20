import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../data/password_recovery_service.dart';
import '../controllers/authentication_controller.dart';
import '../widgets/google_sign_in_button.dart';
import 'password_recovery_pages.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirmation = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _clearError() =>
      ref.read(authenticationControllerProvider.notifier).clearError();

  Future<void> _submit() async {
    if (ref.read(authenticationControllerProvider).isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final created = await ref
        .read(authenticationControllerProvider.notifier)
        .signUp(name: _name.text, email: _email.text, password: _password.text);
    if (!mounted) return;
    if (created) {
      TextInput.finishAutofillContext();
    } else {
      _password.clear();
      _confirmation.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authenticationControllerProvider);
    final busy = action.isLoading;
    final otpEnabled = ref.watch(signupEmailOtpEnabledProvider);
    return RecoveryPage(
      title: 'Create your account',
      description: 'Start your journey to a healthier you with FitNEP.',
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (action.errorMessage != null)
                RecoveryMessage(action.errorMessage!),
              GoogleSignInButton(
                isLoading: busy && action.isGoogleSignIn,
                onPressed: busy
                    ? null
                    : () => ref
                          .read(authenticationControllerProvider.notifier)
                          .signInWithGoogle(rememberSession: true),
              ),
              const AuthenticationDivider(),
              TextFormField(
                controller: _name,
                readOnly: busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  hintText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Enter your name.';
                  if (name.length > 100) return 'Use 100 characters or fewer.';
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                readOnly: busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your email address.'
                    : PasswordRecoveryService.emailError(value),
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                readOnly: busy,
                obscureText: _hidePassword,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: _passwordDecoration(
                  'Password',
                  _hidePassword,
                  busy
                      ? null
                      : () => setState(() => _hidePassword = !_hidePassword),
                ).copyWith(helperText: 'Use at least 8 characters.'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Create a password.';
                  }
                  if (value.length < 8) return 'Use at least 8 characters.';
                  return null;
                },
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmation,
                readOnly: busy,
                obscureText: _hideConfirmation,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                decoration: _passwordDecoration(
                  'Confirm password',
                  _hideConfirmation,
                  busy
                      ? null
                      : () => setState(
                          () => _hideConfirmation = !_hideConfirmation,
                        ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Confirm your password.'
                    : value != _password.text
                    ? 'Passwords do not match.'
                    : null,
                onChanged: (_) => _clearError(),
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(
                  busy && !action.isGoogleSignIn
                      ? 'Creating account\u2026'
                      : 'Create account',
                ),
              ),
              if (otpEnabled) ...[
                const SizedBox(height: 12),
                const Text(
                  'We\u2019ll verify your email with a 6-digit code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Color(0xFF657A8C)),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(child: Text('Already have an account?')),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            _clearError();
                            context.goNamed(AppRoutes.login);
                          },
                    child: const Text('Log in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _passwordDecoration(
    String label,
    bool hidden,
    VoidCallback? toggle,
  ) => InputDecoration(
    labelText: label,
    prefixIcon: const Icon(Icons.lock_outline),
    suffixIcon: IconButton(
      tooltip: hidden ? 'Show $label' : 'Hide $label',
      onPressed: toggle,
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
    ),
  );
}
