import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/password_form_field.dart';
import '../../../app/routes/app_router.dart';
import '../../../app/routes/app_routes.dart';
import '../../../shared/api_client.dart';
import '../../../shared/backend_resolver.dart';
import '../../../shared/firebase_providers.dart';
import '../../../shared/token_storage.dart';
import '../authentication_controller.dart';
import '../sign_out_to_welcome.dart';
import 'password_recovery_pages.dart';

final changeTemporaryPasswordProvider = Provider<Future<void> Function(String)>(
  (ref) {
    return (password) async {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      if (user == null) throw StateError('Sign in to change your password.');
      final api = ApiClient(
        tokenStorage: TokenStorage(auth: auth, expectedUid: user.uid),
        resolveBackend: ref.read(backendResolverProvider).resolve,
        backendUnavailable: ref.read(backendResolverProvider).unavailable,
      );
      try {
        await api.dio.post<void>(
          'auth/staff/change-temporary-password',
          data: {'new_password': password},
        );
      } finally {
        api.dio.close();
      }
    };
  },
);

class ChangeStaffPasswordPage extends ConsumerStatefulWidget {
  const ChangeStaffPasswordPage({super.key});

  @override
  ConsumerState<ChangeStaffPasswordPage> createState() =>
      _ChangeStaffPasswordPageState();
}

class _ChangeStaffPasswordPageState
    extends ConsumerState<ChangeStaffPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _saving = false;
  bool _changed = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(changeTemporaryPasswordProvider)(_password.text);
      if (!mounted) return;
      _password.clear();
      _confirmation.clear();
      setState(() => _changed = true);
      await signOutToWelcome(context, ref);
    } on DioException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = switch (error.response?.statusCode) {
          400 =>
            'Choose a different password that meets the password requirements.',
          401 ||
          403 => 'Sign out and sign in again to finish changing your password.',
          409 => 'Your temporary password expired. Continue with Google to choose a new password.',
          _ => 'Could not confirm the password change. Try again or sign in again.',
        },
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not confirm the password change. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authenticationControllerProvider);
    return RecoveryPage(
      showBackButton: false,
      title: 'Change your temporary password',
      description: _changed
          ? 'Sign out and sign in again with your new password.'
          : 'Choose a new password before continuing to FitNEP.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error ?? action.errorMessage case final String error)
              RecoveryMessage(error),
            if (!_changed) ...[
              PasswordFormField(
                controller: _password,
                enabled: !_saving,
                autofillHints: const [AutofillHints.newPassword],
                label: 'New password',
                validator: (value) {
                  final password = value ?? '';
                  return password.trim().length < 8 ||
                          utf8.encode(password).length > 128
                      ? 'Use at least 8 characters and at most 128 bytes.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              PasswordFormField(
                controller: _confirmation,
                enabled: !_saving,
                label: 'Confirm new password',
                validator: (value) =>
                    value == _password.text ? null : 'Passwords must match.',
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Saving…' : 'Change password'),
              ),
            ],
            if (_error?.contains('expired') == true)
              TextButton(
                onPressed: _saving || action.isLoading
                    ? null
                    : () async {
                        final router = ref.read(appRouterProvider);
                        final auth = ref.read(firebaseAuthProvider);
                        final expectedUid = auth.currentUser?.uid;
                        final success = await ref
                            .read(authenticationControllerProvider.notifier)
                            .signInWithGoogle(rememberSession: true);
                        if (success && auth.currentUser?.uid == expectedUid) {
                          router.go(
                            '${AppRoutes.changeStaffPasswordPath}?recover=google',
                          );
                        }
                      },
                child: const Text('Continue with Google'),
              ),
            TextButton(
              onPressed: _saving || action.isLoading
                  ? null
                  : () => signOutToWelcome(context, ref),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
