import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes/route_access_gate.dart';
import 'data/authorization_repository.dart';
import 'data/account.dart';

class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});
  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  late Future<List<FitNepAccount>> users;
  bool saving = false;
  int inputRevision = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    users = ref
        .read(authorizationRepositoryProvider)
        .all('admin/users', 'users')
        .then((rows) => rows.map(FitNepAccount.fromJson).toList());
  }

  Future<void> _change(FitNepAccount user, Map<String, dynamic> change) async {
    final description = switch (change) {
      {'role': final String role} =>
        'Change ${user.fullName} from ${user.role.label} to ${parseRole(role)!.label}?',
      {'payments_verify': final bool enabled} =>
        '${enabled ? 'Give' : 'Remove'} payment verification access for ${user.fullName}?',
      _ =>
        '${change['account_status'] == 'active' ? 'Activate' : 'Deactivate'} ${user.fullName}\'s account?',
    };
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update account'),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (approved != true) {
      setState(() => inputRevision++);
      return;
    }
    setState(() {
      saving = true;
      inputRevision++;
      error = null;
    });
    try {
      await ref
          .read(authorizationRepositoryProvider)
          .request(
            'admin/users/${Uri.encodeComponent(user.id)}',
            method: 'PATCH',
            data: change,
          );
      if (mounted) {
        setState(_load);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Account updated.')));
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _assign(FitNepAccount client) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final repo = ref.read(authorizationRepositoryProvider);
      final results = await Future.wait([
        repo.all('admin/users', 'users', query: {'role': 'dietitian'}),
        repo.all('admin/users', 'users', query: {'role': 'staff'}),
        repo.all('admin/users', 'users', query: {'role': 'admin'}),
        repo.request(
          'admin/clients/${Uri.encodeComponent(client.id)}/assignment',
        ),
      ]);
      final dietitians = (results[0] as List<Map<String, dynamic>>)
          .map(FitNepAccount.fromJson)
          .where((u) => u.isActive)
          .toList();
      final staff = [
        ...(results[1] as List<Map<String, dynamic>>),
        ...(results[2] as List<Map<String, dynamic>>),
      ].map(FitNepAccount.fromJson).where((u) => u.isActive).toList();
      final current =
          (results[3] as Map<String, dynamic>)['assignment'] as Map?;
      String? dietitian = current?['dietitian_id'] as String?;
      if (!dietitians.any((user) => user.id == dietitian)) dietitian = null;
      final selected = (current?['staff_ids'] as List? ?? [])
          .cast<String>()
          .where((id) => staff.any((user) => user.id == id))
          .toSet();
      if (!mounted) return;
      final save = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Care team for ${client.fullName}'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: dietitian ?? '',
                      decoration: const InputDecoration(
                        labelText: 'Assigned dietitian',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Unassigned'),
                        ),
                        for (final user in dietitians)
                          DropdownMenuItem(
                            value: user.id,
                            child: Text(user.fullName),
                          ),
                      ],
                      onChanged: (value) =>
                          update(() => dietitian = value == '' ? null : value),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Choose additional care team members. Assigned admins can review plans when the client shares nutrition records.',
                    ),
                    for (final user in staff)
                      CheckboxListTile(
                        title: Text(user.fullName),
                        subtitle: Text(user.role.label),
                        value: selected.contains(user.id),
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selected.add(user.id);
                          } else {
                            selected.remove(user.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save assignment'),
              ),
            ],
          ),
        ),
      );
      if (save == true) {
        await repo.request(
          'admin/clients/${Uri.encodeComponent(client.id)}/assignment',
          method: 'PUT',
          data: {'dietitian_id': dietitian, 'staff_ids': selected.toList()},
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Care team updated.')));
        }
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownId = ref.watch(routeSessionProvider).value?.uid;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users and roles'),
        actions: [
          IconButton(
            onPressed: saving ? null : () => setState(_load),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (saving) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: FutureBuilder(
              future: users,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(snapshot.error.toString()),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.isEmpty) {
                  return const Center(child: Text('No accounts found.'));
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final user in snapshot.data!)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.fullName.isEmpty
                                    ? user.email
                                    : user.fullName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(user.email),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<FitNepRole>(
                                key: ValueKey((
                                  user.id,
                                  user.role,
                                  inputRevision,
                                )),
                                initialValue: user.role,
                                decoration: const InputDecoration(
                                  labelText: 'Assigned role',
                                ),
                                items: [
                                  for (final role in FitNepRole.values)
                                    DropdownMenuItem(
                                      value: role,
                                      child: Text(role.label),
                                    ),
                                ],
                                onChanged: saving || ownId == user.id
                                    ? null
                                    : (role) {
                                        if (role != null && role != user.role) {
                                          _change(user, {'role': role.name});
                                        }
                                      },
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Account active'),
                                value: user.isActive,
                                onChanged: saving || ownId == user.id
                                    ? null
                                    : (active) => _change(user, {
                                        'account_status': active
                                            ? 'active'
                                            : 'inactive',
                                      }),
                              ),
                              if (user.role == FitNepRole.staff)
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Can verify payments'),
                                  value: user.paymentsVerify,
                                  onChanged: saving || !user.isActive
                                      ? null
                                      : (enabled) => _change(user, {
                                          'payments_verify': enabled,
                                        }),
                                ),
                              if (user.role == FitNepRole.client &&
                                  user.isActive)
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => _assign(user),
                                  icon: const Icon(Icons.group_add_outlined),
                                  label: const Text('Assign care team'),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
