import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../data/authorization_repository.dart';
import '../domain/account.dart';
import '../domain/profile_age.dart';
import '../../../core/authorization/role_permissions.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, this.onboarding = false});

  final bool onboarding;
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Parent or guardian consent'),
        content: const Text(
          'Ask a parent or guardian to review the Privacy Policy and confirm '
          'that you have permission to provide your health information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => context.pushNamed(AppRoutes.privacyPolicy),
            child: const Text('Read privacy policy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm permission'),
          ),
        ],
      ),
    );
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
        (widget.onboarding || date.isNotEmpty || savedBirthDate != null) &&
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
      if (widget.onboarding) {
        context.goNamed(
          AppRoutes.intakeEditorName,
          queryParameters: {'onboarding': '1'},
        );
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
      }
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
                  child: Text(
                    widget.onboarding
                        ? 'Continue to health intake'
                        : 'Save profile',
                  ),
                ),
                if (widget.onboarding)
                  TextButton(
                    onPressed: saving
                        ? null
                        : () => context.go(AppRoutes.clientHome),
                    child: const Text('Finish later'),
                  )
                else if (current.role == FitNepRole.client) ...[
                  const SizedBox(height: 24),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: const Text('Health information'),
                      subtitle: Text(
                        savedBirthDate == null
                            ? 'Save your date of birth to open your intake'
                            : 'View or edit your intake, measurements and BMI',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: savedBirthDate == null || saving
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
