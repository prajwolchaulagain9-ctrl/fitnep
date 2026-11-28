import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_routes.dart';
import '../onboarding/data/client_onboarding_status.dart';
import 'data/authorization_repository.dart';
import 'data/account.dart';
import 'data/profile_age.dart';
import 'profile_guardian_consent.dart';
import '../../shared/role_permissions.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final name = TextEditingController();
  final birthDate = TextEditingController();
  final contactEmail = TextEditingController();
  final phone = TextEditingController();
  FitNepAccount? account;
  String? savedBirthDate;
  String? error;
  bool loading = true;
  bool saving = false;
  bool guardianConfirmed = false;
  bool guardianDialogOpen = false;

  int? get age => ageFromBirthDate(birthDate.text.trim(), DateTime.now());
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    birthDate.dispose();
    contactEmail.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(authorizationRepositoryProvider)
          .request('profile/me');
      if (mounted) {
        setState(() {
          _applyAccount(data);
          loading = false;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.toString();
          loading = false;
        });
      }
    }
  }

  void _applyAccount(Map<String, dynamic> data) {
    final profile = Map<String, dynamic>.from(data['account'] as Map);
    final result = FitNepAccount.fromJson(profile);
    account = result;
    name.text = result.fullName;
    savedBirthDate = profile['date_of_birth'] as String?;
    birthDate.text = savedBirthDate ?? '';
    contactEmail.text = profile['contact_email'] as String? ?? '';
    phone.text = profile['contact_phone'] as String? ?? '';
    guardianConfirmed = profile['guardian_consent_confirmed'] == true;
  }

  Future<bool> _confirmGuardian() async {
    if (guardianConfirmed || age == null || age! >= 18) return true;
    if (guardianDialogOpen) return false;
    guardianDialogOpen = true;
    final confirmed = await showProfileGuardianConsent(context);
    guardianDialogOpen = false;
    if (!mounted || confirmed != true) return false;
    setState(() => guardianConfirmed = true);
    return true;
  }

  Future<void> _save() async {
    if (saving || guardianDialogOpen) return;
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter your full name.');
      return;
    }
    final isClient = account?.role == FitNepRole.client;
    final date = birthDate.text.trim();
    if (isClient &&
        (date.isNotEmpty || savedBirthDate != null) &&
        age == null) {
      setState(
        () => error = 'Enter a valid date of birth in YYYY-MM-DD format.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    if (isClient && !await _confirmGuardian()) return;
    if (!mounted || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final updated = await ref
          .read(authorizationRepositoryProvider)
          .request(
            'profile/me',
            method: 'PATCH',
            data: {
              'full_name': name.text.trim(),
              if (isClient) ...{
                if (date.isNotEmpty) 'date_of_birth': date,
                'contact_email': _optionalText(contactEmail.text),
                'contact_phone': _optionalText(phone.text),
                'guardian_consent_confirmed': guardianConfirmed,
              },
            },
          );
      if (!mounted) return;
      setState(() => _applyAccount(updated));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = failure.toString();
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My profile')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error != null) ...[
                Text(error!),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ],
              if (account case final current?) ...[
                Text(
                  'Sign-in email',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(current.email),
                const SizedBox(height: 8),
                Text(current.role.label),
                const SizedBox(height: 24),
                TextField(
                  controller: name,
                  enabled: !saving,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                if (current.role == FitNepRole.client) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: birthDate,
                    enabled: !saving,
                    keyboardType: TextInputType.datetime,
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: 'Date of birth',
                      hintText: 'YYYY-MM-DD',
                      helperText: age == null ? null : 'Age ${age!}',
                    ),
                    onChanged: (_) {
                      setState(() {});
                      if (age case final years? when years < 18) {
                        unawaited(_confirmGuardian());
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contactEmail,
                    enabled: !saving,
                    keyboardType: TextInputType.emailAddress,
                    maxLength: 254,
                    decoration: const InputDecoration(
                      labelText: 'Contact email (optional)',
                      helperText: 'Leave blank to use your sign-in email.',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phone,
                    enabled: !saving,
                    keyboardType: TextInputType.phone,
                    maxLength: 32,
                    decoration: const InputDecoration(
                      labelText: 'Phone number (optional)',
                      counterText: '',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving ? null : _save,
                  child: const Text('Save profile'),
                ),
                if (current.role == FitNepRole.client) ...[
                  const SizedBox(height: 24),
                  if (ref
                          .watch(clientOnboardingStatusProvider(current.id))
                          .value ==
                      ClientOnboardingStatus.skipped) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.flag_outlined),
                        title: const Text('Finish setup'),
                        subtitle: const Text('Add your height and weight'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: saving
                            ? null
                            : () => context.pushNamed(
                                AppRoutes.clientOnboardingName,
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: const Text('Health information'),
                      subtitle: const Text(
                        'View or edit your intake, measurements and BMI',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: saving
                          ? null
                          : () => context.pushNamed(AppRoutes.intakeEditorName),
                    ),
                  ),
                ],
              ],
            ],
          ),
  );
}

String? _optionalText(String value) =>
    value.trim().isEmpty ? null : value.trim();
