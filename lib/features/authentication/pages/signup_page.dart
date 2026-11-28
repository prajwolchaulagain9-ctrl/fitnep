import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/legal_links.dart';
import '../../../shared/widgets/password_form_field.dart';
import '../data/password_recovery_service.dart';
import '../authentication_controller.dart';
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
  bool _agreed = false;
  String? _consentError;

  @override
  void dispose() {
    for (final controller in [_name, _email, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _clearError([String? value]) =>
      ref.read(authenticationControllerProvider.notifier).clearError();

  bool _checkAgreement() {
    if (_agreed) return true;
    setState(
      () => _consentError =
          'Agree to the Terms and Conditions and Privacy Policy to continue.',
    );
    return false;
  }

  Future<void> _submit() async {
    if (ref.read(authenticationControllerProvider).isLoading) return;
    FocusScope.of(context).unfocus();
    final valid = _form.currentState!.validate();
    if (!_checkAgreement() || !valid) return;
    final created = await ref
        .read(authenticationControllerProvider.notifier)
        .signUp(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          consent: (age: null, guardianConfirmed: false),
        );
    if (created && mounted) TextInput.finishAutofillContext();
  }

  Future<void> _google() async {
    if (!_checkAgreement()) return;
    await ref
        .read(authenticationControllerProvider.notifier)
        .signInWithGoogle(
          rememberSession: true,
          consent: (age: null, guardianConfirmed: false),
        );
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authenticationControllerProvider);
    final busy = action.isLoading;
    return RecoveryPage(
      title: 'Create your account',
      description: 'Your next step towards better health.',
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (action.errorMessage != null)
                RecoveryMessage(action.errorMessage!),
              TextFormField(
                controller: _name,
                readOnly: busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your name.'
                    : value.trim().length > 100
                    ? 'Use 100 characters or fewer.'
                    : null,
                onChanged: _clearError,
              ),
              const SizedBox(height: 12),
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
                validator: PasswordRecoveryService.emailError,
                onChanged: _clearError,
              ),
              const SizedBox(height: 12),
              PasswordFormField(
                controller: _password,
                label: 'Password',
                enabled: !busy,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) => value == null || value.length < 8
                    ? 'Use at least 8 characters.'
                    : null,
                onChanged: _clearError,
              ),
              const SizedBox(height: 12),
              PasswordFormField(
                controller: _confirmation,
                label: 'Confirm password',
                enabled: !busy,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) => value == null || value.isEmpty
                    ? 'Confirm your password.'
                    : value != _password.text
                    ? 'Passwords do not match.'
                    : null,
                onChanged: _clearError,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const Key('signup_agreement'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'I agree to the Terms and Conditions and Privacy Policy',
                  style: TextStyle(fontSize: 14),
                ),
                value: _agreed,
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        _agreed = value == true;
                        _consentError = null;
                      }),
              ),
              if (_consentError != null) RecoveryMessage(_consentError!),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(
                  busy && !action.isGoogleSignIn
                      ? 'Creating account…'
                      : 'Create account',
                ),
              ),
              const AuthenticationDivider(),
              GoogleSignInButton(
                isLoading: busy && action.isGoogleSignIn,
                onPressed: busy ? null : _google,
              ),
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
              const LegalLinks(),
            ],
          ),
        ),
      ),
    );
  }
}
