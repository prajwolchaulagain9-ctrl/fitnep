import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/entities/package_history_entity.dart';
import '../controllers/package_history_controller.dart';
import '../widgets/empty_state_widget.dart';

class PackageHistoryPage extends ConsumerWidget {
  const PackageHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(packageHistoryControllerProvider);
    final controller = ref.read(packageHistoryControllerProvider.notifier);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Package History'),
            Text(
              '${state.history.length} changes recorded',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: state.isLoading ? null : controller.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _PackageHistoryBody(state: state, onRefresh: controller.refresh),
    );
  }
}

class _PackageHistoryBody extends StatelessWidget {
  final PackageHistoryState state;
  final Future<void> Function() onRefresh;

  const _PackageHistoryBody({required this.state, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null && state.history.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: 'Failed to load package history',
        subtitle: state.errorMessage!,
        actionLabel: 'Retry',
        onAction: onRefresh,
      );
    }
    if (state.history.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.history_rounded,
        title: 'No package changes yet',
        subtitle: 'Package creation and changes will appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        itemCount: state.history.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _PackageHistoryCard(history: state.history[index]),
      ),
    );
  }
}

class _PackageHistoryCard extends StatelessWidget {
  final PackageHistoryEntity history;

  const _PackageHistoryCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(history.action);
    final changes = _changes(history);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_actionIcon(history.action), color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        history.action.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        history.packageName,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd MMM yyyy\nHH:mm')
                      .format(history.changedAt.toLocal()),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 17),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'By ${history.adminName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (changes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 12),
              ...changes.map(
                (change) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ChangeRow(change: change),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final _DisplayChange change;

  const _ChangeRow({required this.change});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          change.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        if (change.previous == null)
          _ValueBox(label: 'New value', value: change.current)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ValueBox(label: 'Previous', value: change.previous!),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 24, 8, 0),
                child: Icon(Icons.arrow_forward_rounded, size: 16),
              ),
              Expanded(
                child: _ValueBox(label: 'New', value: change.current),
              ),
            ],
          ),
      ],
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final String value;

  const _ValueBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _DisplayChange {
  final String label;
  final String? previous;
  final String current;

  const _DisplayChange({
    required this.label,
    required this.previous,
    required this.current,
  });
}

List<_DisplayChange> _changes(PackageHistoryEntity history) {
  const fieldLabels = <String, String>{
    'name': 'Package name',
    'price': 'Price',
    'duration_months': 'Duration',
    'feature_description': 'Features',
    'is_active': 'Status',
  };
  final fields = <String>{
    ...?history.previousValues?.keys,
    ...history.newValues.keys,
  };
  return fieldLabels.keys
      .where(fields.contains)
      .map(
        (field) => _DisplayChange(
          label: fieldLabels[field]!,
          previous: history.previousValues?.containsKey(field) == true
              ? _formatValue(field, history.previousValues![field])
              : null,
          current: _formatValue(field, history.newValues[field]),
        ),
      )
      .toList(growable: false);
}

String _formatValue(String field, Object? value) {
  if (field == 'price' && value is num) {
    return NumberFormat.currency(
      locale: 'en_NP',
      symbol: 'NPR ',
      decimalDigits: value % 1 == 0 ? 0 : 2,
    ).format(value);
  }
  if (field == 'duration_months' && value is num) {
    final months = value.toInt();
    return '$months ${months == 1 ? 'month' : 'months'}';
  }
  if (field == 'is_active' && value is bool) {
    return value ? 'Active' : 'Inactive';
  }
  return value?.toString() ?? 'Not set';
}

Color _actionColor(PackageHistoryAction action) {
  switch (action) {
    case PackageHistoryAction.created:
      return AppColors.info;
    case PackageHistoryAction.updated:
      return AppColors.actionPackageChange;
    case PackageHistoryAction.activated:
      return AppColors.statusActive;
    case PackageHistoryAction.deactivated:
      return AppColors.statusInactive;
  }
}

IconData _actionIcon(PackageHistoryAction action) {
  switch (action) {
    case PackageHistoryAction.created:
      return Icons.add_box_outlined;
    case PackageHistoryAction.updated:
      return Icons.edit_outlined;
    case PackageHistoryAction.activated:
      return Icons.check_circle_outline_rounded;
    case PackageHistoryAction.deactivated:
      return Icons.block_rounded;
  }
}
