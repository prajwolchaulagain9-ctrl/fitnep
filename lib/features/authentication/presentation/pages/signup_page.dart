import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../data/password_recovery_service.dart';
import '../../domain/entities/privacy_policy.dart';
import '../controllers/authentication_controller.dart';
import '../widgets/google_sign_in_button.dart';
import 'password_recovery_pages.dart';
import 'privacy_policy_page.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _age = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _hidePassword = true;
  bool _hideConfirmation = true;
  Timer? _reviewTimer;
  bool _reviewing = false;

  @override
  void dispose() {
    _reviewTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _age.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _clearError() =>
      ref.read(authenticationControllerProvider.notifier).clearError();

  static String? _nameError(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your name.';
    if (name.length > 100) return 'Use 100 characters or fewer.';
    return null;
  }

  static String? _emailError(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your email address.';
    }
    return PasswordRecoveryService.emailError(value);
  }

  static String? _passwordError(String? value) {
    if (value == null || value.isEmpty) return 'Create a password.';
    if (value.length < 8) return 'Use at least 8 characters.';
    return null;
  }

  String? _confirmationError(String? value) {
    if (value == null || value.isEmpty) return 'Confirm your password.';
    return value != _password.text ? 'Passwords do not match.' : null;
  }

  void _schedulePolicyReview() {
    _reviewTimer?.cancel();
    if (_reviewing ||
        _nameError(_name.text) != null ||
        _emailError(_email.text) != null ||
        parseRegistrationAge(_age.text) == null ||
        _passwordError(_password.text) != null ||
        _confirmationError(_confirmation.text) != null) {
      return;
    }
    _reviewTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        _reviewPolicy();
      }
    });
  }

  Future<void> _reviewPolicy() async {
    _reviewTimer?.cancel();
    if (_reviewing || ref.read(authenticationControllerProvider).isLoading) {
      return;
    }
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final age = parseRegistrationAge(_age.text)!;
    final name = _name.text;
    final email = _email.text;
    final password = _password.text;
    _reviewing = true;
    final accepted = await PrivacyPolicyPage.review(context, age: age);
    if (!mounted) return;
    _reviewing = false;
    if (accepted != true) return;

    final created = await ref
        .read(authenticationControllerProvider.notifier)
        .signUp(
          name: name,
          email: email,
          password: password,
          consent: (age: age, guardianConfirmed: age < 18),
        );
    if (!mounted) return;
    if (created) {
      TextInput.finishAutofillContext();
    } else {
      _password.clear();
      _confirmation.clear();
    }
  }

  void _signInWithGoogle() {
    _reviewTimer?.cancel();
    ref
        .read(authenticationControllerProvider.notifier)
        .signInWithGoogle(rememberSession: true);
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authenticationControllerProvider);
    final busy = action.isLoading;
    return RecoveryPage(
      title: 'Create your account',
      description: 'Start your journey to a healthier you with FitNEP.',
      child: AutofillGroup(
        child: Form(
          key: _form,
          onChanged: _schedulePolicyReview,
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
                  hintText: 'Your name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: _nameError,
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
                validator: _emailError,
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _age,
                readOnly: busy,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Age in years'),
                validator: (value) => parseRegistrationAge(value) == null
                    ? 'Enter an age from 1 to 120.'
                    : null,
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
                validator: _passwordError,
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
                validator: _confirmationError,
                onChanged: (_) => _clearError(),
                onFieldSubmitted: (_) => _reviewPolicy(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : _reviewPolicy,
                child: Text(
                  busy && !action.isGoogleSignIn
                      ? 'Creating account\u2026'
                      : 'Continue',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'We\u2019ll ask you to verify your email.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF657A8C)),
              ),
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
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        _reviewTimer?.cancel();
                        context.pushNamed(AppRoutes.privacyPolicy);
                      },
                child: const Text('Read Privacy Policy'),
              ),
              const AuthenticationDivider(),
              GoogleSignInButton(
                isLoading: busy && action.isGoogleSignIn,
                onPressed: busy ? null : _signInWithGoogle,
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
