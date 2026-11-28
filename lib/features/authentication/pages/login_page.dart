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

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final action = ref.read(authenticationControllerProvider);
    if (action.isLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final signedIn = await ref
        .read(authenticationControllerProvider.notifier)
        .signIn(
          email: _emailController.text,
          password: _passwordController.text,
          rememberSession: _rememberMe,
        );
    if (!mounted) return;
    if (signedIn) {
      TextInput.finishAutofillContext();
    } else {
      _passwordController.clear();
    }
  }

  void _clearError() {
    ref.read(authenticationControllerProvider.notifier).clearError();
  }

  void _setRememberMe(bool value) {
    _clearError();
    setState(() => _rememberMe = value);
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authenticationControllerProvider);
    final busy = action.isLoading;

    return RecoveryPage(
      title: 'Welcome back',
      description: 'Log in to your FitNEP account.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (action.errorMessage != null)
                RecoveryMessage(action.errorMessage!),
              TextFormField(
                controller: _emailController,
                readOnly: busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: PasswordRecoveryService.emailError,
                onChanged: (_) => _clearError(),
              ),
              const SizedBox(height: 12),
              PasswordFormField(
                controller: _passwordController,
                label: 'Password',
                enabled: !busy,
                autofillHints: const [AutofillHints.password],
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your password.'
                    : null,
                onChanged: (_) => _clearError(),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: busy ? null : () => _setRememberMe(!_rememberMe),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: busy
                              ? null
                              : (value) => _setRememberMe(value ?? false),
                        ),
                        const Flexible(child: Text('Remember me')),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => context.pushNamed(AppRoutes.forgotPassword),
                    child: const Text('Forgot password?'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: busy ? null : _submit,
                child: Text(
                  busy && !action.isGoogleSignIn
                      ? 'Logging in\u2026'
                      : 'Log in',
                ),
              ),
              const AuthenticationDivider(),
              GoogleSignInButton(
                isLoading: busy && action.isGoogleSignIn,
                onPressed: busy
                    ? null
                    : () => ref
                          .read(authenticationControllerProvider.notifier)
                          .signInWithGoogle(rememberSession: _rememberMe),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Flexible(child: Text("Don't have an account?")),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            _clearError();
                            context.pushNamed(AppRoutes.signup);
                          },
                    child: const Text('Sign up'),
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
