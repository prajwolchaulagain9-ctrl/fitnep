import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../data/registration_privacy.dart';
import '../../domain/entities/privacy_policy.dart';
import '../controllers/authentication_controller.dart';
import '../sign_out_to_welcome.dart';
import 'privacy_policy_page.dart';

class RegistrationPrivacyGate extends ConsumerWidget {
  const RegistrationPrivacyGate({required this.child, this.uid, super.key});
  final Widget child;
  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = this.uid ?? ref.watch(authenticationStateProvider).value?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final provider = registrationAcceptedProvider(uid);
    return ref
        .watch(provider)
        .when(
          skipLoadingOnRefresh: false,
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error is FirebaseFunctionsException &&
                                error.code == 'not-found'
                            ? 'The privacy service is unavailable.'
                            : 'Could not check your privacy policy acceptance.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your account is saved. You can sign in with the same '
                        'account to finish registration.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(provider),
                        child: const Text('Try again'),
                      ),
                      const _SwitchAccount(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          data: (accepted) =>
              accepted ? child : _ConsentForm(key: ValueKey(uid), uid: uid),
        );
  }
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
      child: const Text('Use another account'),
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
  int? _age;
  bool _busy = false;
  String? _error;

  Future<void> _reviewAndSave() async {
    final age = _age;
    if (_busy || age == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final accepted = await PrivacyPolicyPage.review(context, age: age);
      if (!mounted || accepted != true) return;
      await acceptRegistrationPrivacy(
        ref.read(registrationPrivacyProvider),
        widget.uid,
        (age: age, guardianConfirmed: age < 18),
      );
      if (mounted) ref.invalidate(registrationAcceptedProvider(widget.uid));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm your acceptance. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complete registration')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            enabled: !_busy,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Age in years',
              helperText: 'Enter your age from 1 to 120.',
            ),
            onChanged: (value) =>
                setState(() => _age = parseRegistrationAge(value)),
            onSubmitted: (_) => _reviewAndSave(),
          ),
          const SizedBox(height: 16),
          if (_error case final message?) Text(message),
          FilledButton(
            onPressed: !_busy && _age != null ? _reviewAndSave : null,
            child: Text(_busy ? 'Saving…' : 'Review Privacy Policy'),
          ),
          const _SwitchAccount(),
        ],
      ),
    ),
  );
}
