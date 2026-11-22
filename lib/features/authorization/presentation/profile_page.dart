import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/authorization_repository.dart';
import '../domain/account.dart';
import '../../../core/authorization/role_permissions.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final name = TextEditingController();
  FitNepAccount? account;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await ref
          .read(authorizationRepositoryProvider)
          .request('profile/me');
      final result = FitNepAccount.fromJson(
        Map<String, dynamic>.from(data['account'] as Map),
      );
      if (mounted) {
        setState(() {
          account = result;
          name.text = result.fullName;
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

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Enter your full name.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await ref
          .read(authorizationRepositoryProvider)
          .request(
            'profile/me',
            method: 'PATCH',
            data: {'full_name': name.text.trim()},
          );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Profile updated.')));
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
                  current.email,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(current.role.label),
                const SizedBox(height: 24),
                TextField(
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save profile'),
                ),
              ],
            ],
          ),
  );
}
