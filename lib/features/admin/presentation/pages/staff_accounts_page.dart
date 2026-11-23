import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/password_form_field.dart';
import '../../../../app/routes/app_routes.dart';
import '../../../../app/routes/route_access_gate.dart';
import '../../data/repositories/staff_account_repository.dart';
import '../../domain/entities/staff_account_entity.dart';
import '../widgets/staff_records_list.dart';

class StaffAccountsPage extends ConsumerStatefulWidget {
  const StaffAccountsPage({super.key});

  @override
  ConsumerState<StaffAccountsPage> createState() => _StaffAccountsPageState();
}

class _StaffAccountsPageState extends ConsumerState<StaffAccountsPage> {
  int _revision = 0;
  bool _changingStatus = false;
  final _statusRequestIds = <(String, bool), String>{};

  Future<void> _edit(
    StaffAccountRepository repository,
    String adminUid, [
    StaffAccount? account,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StaffAccountEditor(
        repository: repository,
        adminUid: adminUid,
        account: account,
      ),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _changeStatus(
    StaffAccountRepository repository,
    StaffAccount account,
  ) async {
    final active = !account.isActive;
    final label = active ? 'Reactivate' : 'Deactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label ${account.displayName}?'),
        content: Text(
          active ? 'They will be able to sign in again.' : 'They will lose access immediately. Their account and history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _changingStatus) return;

    final operation = (account.uid, active);
    final requestId = _statusRequestIds.putIfAbsent(operation, _newRequestId);
    setState(() => _changingStatus = true);
    try {
      final updated = await repository.setActive(
        account.uid,
        requestId,
        active,
      );
      _statusRequestIds.removeWhere((key, _) => key.$1 == account.uid);
      if (!mounted) return;
      _reload();
      if (updated.isActive != active) {
        throw const StaffAccountFailure(
          'The account status changed. Review it and try again.',
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_saveError(error))));
      }
    } finally {
      if (mounted) setState(() => _changingStatus = false);
    }
  }

  void _reload() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    final adminUid = ref.watch(routeSessionProvider).requireValue!.uid;
    final repository = ref.watch(staffAccountRepositoryProvider(adminUid));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff accounts'),
        actions: [
          IconButton(
            onPressed: _changingStatus ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.adminStaffHistory),
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Staff account history',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _changingStatus
                    ? null
                    : () => _edit(repository, adminUid),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Create staff account'),
              ),
            ),
            if (_changingStatus) const LinearProgressIndicator(),
            Expanded(
              child: StaffRecordsList<StaffAccount>(
                key: ValueKey(_revision),
                load: repository.list,
                emptyMessage: 'No staff accounts found.',
                buildItem: (account) => Card(
                  child: ListTile(
                    title: Text(account.displayName),
                    subtitle: Text(
                      [
                        if (account.email case final email?
                            when email != account.displayName)
                          email,
                        account.role.label,
                        account.isActive ? 'Active' : 'Inactive',
                      ].join(' • '),
                    ),
                    trailing: PopupMenuButton<bool>(
                      enabled: !_changingStatus,
                      tooltip: 'Manage ${account.displayName}',
                      onSelected: (edit) {
                        if (edit) {
                          _edit(repository, adminUid, account);
                        } else {
                          _changeStatus(repository, account);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: true,
                          child: Text('Edit account'),
                        ),
                        if (account.uid != adminUid)
                          PopupMenuItem(
                            value: false,
                            child: Text(
                              account.isActive ? 'Deactivate' : 'Reactivate',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffAccountEditor extends StatefulWidget {
  const _StaffAccountEditor({
    required this.repository,
    required this.adminUid,
    this.account,
  });

  final StaffAccountRepository repository;
  final String adminUid;
  final StaffAccount? account;

  @override
  State<_StaffAccountEditor> createState() => _StaffAccountEditorState();
}

class _StaffAccountEditorState extends State<_StaffAccountEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account?.name);
  late final _email = TextEditingController(text: widget.account?.email);
  final _password = TextEditingController();
  late StaffRole _role = widget.account?.role ?? StaffRole.staff;
  Map<String, String>? _lastFields;
  String? _requestId;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final account = widget.account;
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final fields = {
      if (account == null || name != (account.name ?? '')) 'name': name,
      if (account == null || email != (account.email ?? '').toLowerCase())
        'email': email,
      if (account == null || _role != account.role) 'role': _role.name,
      if (account == null) 'temporary_password': _password.text,
    };
    if (fields.isEmpty) {
      Navigator.pop(context);
      return;
    }
    if (!mapEquals(fields, _lastFields)) {
      _requestId = _newRequestId();
      _lastFields = fields;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (account == null) {
        await widget.repository.create(_requestId!, fields);
      } else {
        await widget.repository.update(account.uid, _requestId!, fields);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = _saveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final ownAccount = account?.uid == widget.adminUid;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          account == null ? 'Create staff account' : 'Edit staff account',
        ),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Name'),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (account != null && name == (account.name ?? '')) {
                    return null;
                  }
                  return name.isEmpty || name.length > 100
                      ? 'Enter a name of up to 100 characters.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_saving && !ownAccount,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (account != null && email == (account.email ?? '')) {
                    return null;
                  }
                  return email.length > 254 ||
                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                      ? 'Enter a valid email address.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<StaffRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final role in StaffRole.values)
                    DropdownMenuItem(value: role, child: Text(role.label)),
                ],
                onChanged: _saving || ownAccount
                    ? null
                    : (role) => setState(() => _role = role!),
              ),
              if (account == null) ...[
                const SizedBox(height: 12),
                PasswordFormField(
                  controller: _password,
                  enabled: !_saving,
                  label: 'Temporary password',
                  validator: (value) {
                    final password = value ?? '';
                    return password.trim().length < 8 ||
                            utf8.encode(password).length > 128
                        ? 'Use at least 8 characters and at most 128 bytes.'
                        : null;
                  },
                ),
              ],
              if (_error case final message?) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? 'Saving…'
                  : account == null
                  ? 'Create'
                  : 'Save changes',
            ),
          ),
        ],
      ),
    );
  }
}

String _newRequestId() {
  final random = Random.secure();
  return base64UrlEncode(List.generate(24, (_) => random.nextInt(256)));
}

String _saveError(Object error) => error is StaffAccountFailure
    ? error.message
    : 'Could not confirm the change. Try again.';
