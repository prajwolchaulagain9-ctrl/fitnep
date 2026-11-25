import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../data/registration_privacy.dart';
import '../controllers/authentication_controller.dart';
import '../sign_out_to_welcome.dart';
import '../../../../shared/widgets/legal_links.dart';
import '../../../../shared/widgets/wellness_illustration.dart';
import '../../../../app/theme/theme_mode_controller.dart';

class RegistrationPrivacyGate extends ConsumerWidget {
  const RegistrationPrivacyGate({required this.child, this.uid, super.key});
  final Widget child;
  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = this.uid ?? ref.watch(authenticationStateProvider).value?.uid;
    if (uid == null) {
      return const _PrivacyCheckPage();
    }
    final provider = registrationAcceptedProvider(uid);
    return ref
        .watch(provider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () => const _PrivacyCheckPage(),
          error: (error, _) => _PrivacyCheckPage(
            errorMessage: _privacyError(error),
            onRetry: () => ref.invalidate(provider),
          ),
          data: (accepted) =>
              accepted ? child : _ConsentForm(key: ValueKey(uid), uid: uid),
        );
  }
}

String _privacyError(Object error) => switch (error) {
  TimeoutException() => 'The privacy check took too long. Please try again.',
  FirebaseFunctionsException(
    code: 'not-found' || 'unimplemented' || 'unavailable',
  ) =>
    'The privacy service is temporarily unavailable.',
  _ => 'Could not confirm your privacy policy acceptance.',
};

class _PrivacyCheckPage extends StatelessWidget {
  const _PrivacyCheckPage({this.errorMessage, this.onRetry});

  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Privacy check'),
      automaticallyImplyLeading: false,
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorMessage == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
              ],
              Text(
                errorMessage ?? 'Checking your privacy policy acceptance…',
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Your account is saved. You can try again here or sign in later to finish.',
                  textAlign: TextAlign.center,
                ),
                TextButton(onPressed: onRetry, child: const Text('Try again')),
              ],
              TextButton(
                onPressed: () => context.pushNamed(AppRoutes.privacyPolicy),
                child: const Text('Read Privacy Policy'),
              ),
              const _SwitchAccount(),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SwitchAccount extends ConsumerWidget {
  const _SwitchAccount();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(authenticationControllerProvider);
    return TextButton(
      onPressed: action.isLoading
          ? null
          : () async {
              final signedOut = await signOutToWelcome(context, ref);
              if (!signedOut && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not sign out. Please try again.'),
                  ),
                );
              }
            },
      child: Text(action.isLoading ? 'Signing out…' : 'Use another account'),
    );
  }
}

class _ConsentForm extends ConsumerStatefulWidget {
  const _ConsentForm({required this.uid, super.key});
  final String uid;
  @override
  ConsumerState<_ConsentForm> createState() => _ConsentFormState();
}

class _ConsentFormState extends ConsumerState<_ConsentForm> {
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_busy || !_agreed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await acceptRegistrationPrivacy(
        ref.read(registrationPrivacyProvider),
        widget.uid,
        (age: null, guardianConfirmed: false),
      );
      if (mounted) ref.invalidate(registrationAcceptedProvider(widget.uid));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save your agreement. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Complete registration'),
      actions: const [ThemeModeButton()],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Before you continue',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(width: 12),
              const WellnessIllustration(scene: WellnessScene.care, size: 76),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Review our terms and how FitNEP handles your data.'),
          const LegalLinks(),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I agree to the Terms and Conditions and Privacy Policy',
            ),
            value: _agreed,
            onChanged: _busy
                ? null
                : (value) => setState(() => _agreed = value == true),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: _agreed && !_busy ? _save : null,
            child: Text(_busy ? 'Saving…' : 'Agree and continue'),
          ),
          const _SwitchAccount(),
        ],
      ),
    ),
  );
}
