import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../data/registration_privacy.dart';
import '../controllers/authentication_controller.dart';
import '../sign_out_to_welcome.dart';

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
  int? age;
  bool accepted = false, guardian = false, saving = false;
  String? error;

  Future<void> submit() async {
    final years = age;
    if (saving ||
        years == null ||
        years < 1 ||
        years > 120 ||
        !accepted ||
        (years < 18 && !guardian)) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await acceptRegistrationPrivacy(
        ref,
        widget.uid,
        years,
        accepted,
        guardian,
      );
      if (mounted) ref.invalidate(registrationAcceptedProvider(widget.uid));
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not confirm your acceptance. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = age;
    final validAge = years != null && years >= 1 && years <= 120;
    return Scaffold(
      appBar: AppBar(title: const Text('Complete registration')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextButton(
              onPressed: () => context.pushNamed(AppRoutes.privacyPolicy),
              child: const Text('Read the Privacy Policy'),
            ),
            TextField(
              enabled: !saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Age in years',
                helperText: 'Enter your age from 1 to 120.',
              ),
              onChanged: (value) => setState(() {
                age = int.tryParse(value.trim());
                guardian = false;
              }),
            ),
            CheckboxListTile(
              title: const Text('I accept the FitNEP Privacy Policy'),
              value: accepted,
              onChanged: saving
                  ? null
                  : (v) => setState(() => accepted = v == true),
            ),
            if (validAge && years < 18)
              CheckboxListTile(
                title: const Text('My parent or guardian has given permission'),
                value: guardian,
                onChanged: saving
                    ? null
                    : (v) => setState(() => guardian = v == true),
              ),
            if (error != null) Text(error!),
            FilledButton(
              onPressed:
                  !saving && validAge && accepted && (years >= 18 || guardian)
                  ? submit
                  : null,
              child: Text(saving ? 'Saving…' : 'Continue'),
            ),
            const _SwitchAccount(),
          ],
        ),
      ),
    );
  }
}
