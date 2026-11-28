import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes/route_access_gate.dart';
import '../data/staff_account_repository.dart';
import '../data/staff_account_entity.dart';
import '../widgets/staff_records_list.dart';

class StaffAccountHistoryPage extends ConsumerWidget {
  const StaffAccountHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUid = ref.watch(routeSessionProvider).requireValue!.uid;
    final repository = ref.watch(staffAccountRepositoryProvider(adminUid));
    final locale = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Staff account history')),
      body: SafeArea(
        child: StaffRecordsList<StaffAccountHistoryEntry>(
          load: repository.history,
          emptyMessage: 'No staff account changes have been recorded.',
          buildItem: (entry) {
            final after = entry.after;
            final before = entry.before;
            final date = entry.completedAt.toLocal();
            final timestamp =
                '${locale.formatShortDate(date)} '
                '${locale.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
            return Card(
              child: ExpansionTile(
                title: Text(entry.action.label),
                subtitle: Text(
                  '${after.displayName}\nBy ${entry.actor} • $timestamp',
                ),
                leading: const Icon(Icons.history_rounded),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (before == null || before.name != after.name)
                    _AuditField('Name', before?.name, after.name),
                  if (before == null || before.email != after.email)
                    _AuditField('Email', before?.email, after.email),
                  if (before == null || before.role != after.role)
                    _AuditField('Role', before?.role.label, after.role.label),
                  if (before == null || before.isActive != after.isActive)
                    _AuditField(
                      'Status',
                      before == null ? null : _status(before),
                      _status(after),
                    ),
                  _AuditField('Account ID', null, after.uid),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _status(StaffAccount account) =>
    account.isActive ? 'Active' : 'Inactive';

class _AuditField extends StatelessWidget {
  const _AuditField(this.label, this.before, this.after);

  final String label;
  final String? before;
  final String? after;

  @override
  Widget build(BuildContext context) {
    final value = after ?? 'None';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(before == null ? value : '$before → $value'),
        ],
      ),
    );
  }
}
