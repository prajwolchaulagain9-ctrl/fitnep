import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../client_profile_controller.dart';
import '../widgets/status_badge.dart';
import '../widgets/deactivation_dialog.dart';
import '../widgets/payment_history_tile.dart';
import '../widgets/audit_log_tile.dart';
import '../widgets/empty_state_widget.dart';
import '../data/client_entity.dart';
import '../data/staff_account_entity.dart';
import '../data/client_assignment_repository.dart';
import '../data/staff_account_repository.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/routes/app_routes.dart';

class ClientProfilePage extends ConsumerWidget {
  final String clientId;
  const ClientProfilePage({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(clientProfileControllerProvider(clientId));
    final controller = ref.read(
      clientProfileControllerProvider(clientId).notifier,
    );

    // Show snack on success/error messages
    ref.listen<ClientProfileState>(clientProfileControllerProvider(clientId), (
      ClientProfileState? prev,
      ClientProfileState next,
    ) {
      if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.statusActive,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Flexible(child: Text(next.successMessage!)),
              ],
            ),
          ),
        );
        controller.clearMessages();
      }
      if (next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.statusInactive,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(next.errorMessage!)),
              ],
            ),
          ),
        );
        controller.clearMessages();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.client == null
          ? EmptyStateWidget(
              title: 'Client not found',
              subtitle: 'The client profile could not be loaded.',
              icon: Icons.person_off_outlined,
            )
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: CustomScrollView(
                  slivers: [
                    _buildSliverAppBar(context, state, controller),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          if (!state.client!.isActive)
                            _DeactivationNotice(client: state.client!),
                          const SizedBox(height: 20),
                          _AssignmentSection(
                            state: state,
                            onAssign: () => _handleAssign(
                              context,
                              state.client!,
                              controller,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _PersonalInfoSection(client: state.client!),
                          const SizedBox(height: 16),
                          _PackageSection(client: state.client!),
                          const SizedBox(height: 16),
                          if (state.client!.hasFinancialSummary)
                            _PaymentSummarySection(client: state.client!),
                          const SizedBox(height: 16),
                          _PaymentHistorySection(client: state.client!),
                          const SizedBox(height: 16),
                          _PackageHistorySection(client: state.client!),
                          if (state.auditLogs.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _AuditSection(state: state),
                          ],
                          const SizedBox(height: 24),
                          _ActionButton(
                            state: state,
                            onDeactivate: () =>
                                _handleDeactivate(context, controller),
                            onReactivate: () =>
                                _handleReactivate(context, controller),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _handleAssign(
    BuildContext context,
    ClientEntity client,
    ClientProfileController controller,
  ) async {
    final selected = await showDialog<StaffAccount>(
      context: context,
      builder: (_) => _DietitianPicker(client: client),
    );
    if (selected != null && context.mounted) {
      await controller.assignDietitian(selected);
    }
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    ClientProfileState state,
    ClientProfileController controller,
  ) {
    final client = state.client!;
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      flexibleSpace: FlexibleSpaceBar(
        background: _ProfileHeader(client: client),
        collapseMode: CollapseMode.parallax,
      ),
      actions: [
        IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () {}),
      ],
    );
  }

  Future<void> _handleDeactivate(
    BuildContext context,
    ClientProfileController controller,
  ) async {
    final reason = await showDeactivationDialog(context);
    if (reason != null && reason.isNotEmpty) {
      await controller.deactivateClient(reason);
    }
  }

  Future<void> _handleReactivate(
    BuildContext context,
    ClientProfileController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivate Account'),
        content: const Text(
          'Are you sure you want to reactivate this client\'s account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.reactivateClient();
    }
  }
}

// ── Sections ────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final ClientEntity client;
  const _ProfileHeader({required this.client});

  static const _colors = [
    AppColors.primary,
    AppColors.info,
    AppColors.actionPackageChange,
    AppColors.warning,
    AppColors.error,
    AppColors.success,
  ];

  Color get _color {
    final hash = client.name.codeUnits.fold(0, (p, e) => p + e);
    return _colors[hash % _colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surface,
            _color.withValues(alpha: 0.08),
          ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _color.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    client.initials,
                    style: TextStyle(
                      color: _color,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        client.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    StatusBadge(status: client.status, large: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeactivationNotice extends StatelessWidget {
  final ClientEntity client;
  const _DeactivationNotice({required this.client});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.statusInactiveContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.statusInactive.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.block_rounded,
            color: AppColors.statusInactive,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Account Deactivated',
                  style: TextStyle(
                    color: AppColors.statusInactive,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (client.deactivationReason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reason: ${client.deactivationReason}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.statusInactive.withValues(alpha: 0.8),
                      height: 1.5,
                    ),
                  ),
                ],
                if (client.deactivatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Deactivated on: ${DateFormat('dd MMM yyyy').format(client.deactivatedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.statusInactive.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalInfoSection extends StatelessWidget {
  final ClientEntity client;
  const _PersonalInfoSection({required this.client});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Personal Information',
      icon: Icons.person_outline_rounded,
      children: [
        _InfoRow('Email', client.email, Icons.email_outlined),
        _InfoRow('Phone', client.phone, Icons.phone_outlined),
        _InfoRow(
          'Gender',
          client.gender.name[0].toUpperCase() + client.gender.name.substring(1),
          Icons.wc_rounded,
        ),
        _InfoRow(
          'Date of Birth',
          client.dateOfBirth == null
              ? 'Not provided'
              : '${DateFormat('dd MMM yyyy').format(client.dateOfBirth!)} (${client.age} yrs)',
          Icons.cake_outlined,
        ),
        _InfoRow('Address', client.address, Icons.location_on_outlined),
        _InfoRow(
          'Member Since',
          DateFormat('dd MMM yyyy').format(client.joinDate),
          Icons.calendar_today_outlined,
        ),
      ],
    );
  }
}

class _PackageSection extends StatelessWidget {
  final ClientEntity client;
  const _PackageSection({required this.client});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Current Package',
      icon: Icons.inventory_2_outlined,
      children: [
        _InfoRow('Package', client.packageName, Icons.inventory_2_outlined),
        if (client.packageStatus case final status?)
          _InfoRow(
            'Membership status',
            status[0].toUpperCase() + status.substring(1),
            Icons.schedule_outlined,
          ),
      ],
    );
  }
}

class _AssignmentSection extends StatelessWidget {
  const _AssignmentSection({required this.state, required this.onAssign});

  final ClientProfileState state;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final client = state.client!;
    final hasDietitian = client.assignedDietitianId.isNotEmpty;
    return _SectionCard(
      title: 'Dietitian assignment',
      icon: Icons.medical_services_outlined,
      children: [
        Text(
          client.dietitianLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (!client.isActive) ...[
          const SizedBox(height: 4),
          Text(
            'The assignment takes effect when the account is reactivated.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: !state.isAssigning && !state.isDeactivating
                ? onAssign
                : null,
            icon: state.isAssigning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.assignment_ind_outlined),
            label: Text(
              state.isAssigning
                  ? 'Saving assignment…'
                  : hasDietitian
                  ? 'Change dietitian'
                  : 'Assign dietitian',
            ),
          ),
        ),
        if (client.isActive && hasDietitian)
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => context.pushNamed(
                AppRoutes.adminClientPlansName,
                pathParameters: {'id': client.id},
              ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review diet plans'),
            ),
          ),
      ],
    );
  }
}

class _DietitianPicker extends ConsumerWidget {
  const _DietitianPicker({required this.client});

  final ClientEntity client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dietitians = ref.watch(activeDietitiansProvider);
    return AlertDialog(
      title: Text(
        client.assignedDietitianId.isEmpty
            ? 'Assign dietitian'
            : 'Change dietitian',
      ),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: dietitians.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(switch (error) {
                StaffAccountFailure(:final message) => message,
                ClientAssignmentFailure(:final message) => message,
                _ => 'Unable to load dietitians.',
              }),
              TextButton(
                onPressed: () => ref.invalidate(activeDietitiansProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (options) => options.isEmpty
              ? const Text('No active dietitians are available.')
              : Column(
                  children: [
                    for (final option in options)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.dietitian.displayName),
                        subtitle: option.clientCountLabel == null
                            ? null
                            : Text(option.clientCountLabel!),
                        selected:
                            option.dietitian.uid == client.assignedDietitianId,
                        trailing:
                            option.dietitian.uid == client.assignedDietitianId
                            ? const Icon(
                                Icons.check,
                                semanticLabel: 'Currently assigned',
                              )
                            : null,
                        onTap:
                            option.dietitian.uid == client.assignedDietitianId
                            ? null
                            : () => Navigator.pop(context, option.dietitian),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PaymentSummarySection extends StatelessWidget {
  final ClientEntity client;
  const _PaymentSummarySection({required this.client});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Payment Summary',
      icon: Icons.account_balance_wallet_outlined,
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                label: 'Total Paid',
                value: 'Rs. ${client.totalAmountPaid.toStringAsFixed(0)}',
                color: AppColors.statusActive,
                icon: Icons.check_circle_outline_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SummaryCard(
                label: 'Outstanding',
                value: 'Rs. ${client.outstandingAmount.toStringAsFixed(0)}',
                color: client.outstandingAmount > 0
                    ? AppColors.statusInactive
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                icon: Icons.pending_outlined,
              ),
            ),
          ],
        ),
        if (client.lastPaymentDate != null) ...[
          const SizedBox(height: 10),
          _InfoRow(
            'Last Payment',
            DateFormat('dd MMM yyyy').format(client.lastPaymentDate!),
            Icons.payment_rounded,
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentHistorySection extends StatelessWidget {
  final ClientEntity client;
  const _PaymentHistorySection({required this.client});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Payment History',
      icon: Icons.history_rounded,
      children: [
        if (client.paymentHistory.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No payment records.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...client.paymentHistory.asMap().entries.map((entry) {
            final i = entry.key;
            return PaymentHistoryTile(
              payment: entry.value,
              isLast: i == client.paymentHistory.length - 1,
            );
          }),
      ],
    );
  }
}

class _PackageHistorySection extends StatelessWidget {
  final ClientEntity client;
  const _PackageHistorySection({required this.client});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Package History',
      icon: Icons.swap_horiz_rounded,
      children: client.packageHistory.map((entry) {
        final isCurrent = entry.endDate == null;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.packageName,
                          style: TextStyle(
                            color: isCurrent
                                ? Theme.of(context).colorScheme.onSurface
                                : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            fontWeight: isCurrent
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontSize: 14,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Current',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      isCurrent
                          ? 'Since ${DateFormat('dd MMM yyyy').format(entry.startDate)}'
                          : '${DateFormat('dd MMM yyyy').format(entry.startDate)} – ${DateFormat('dd MMM yyyy').format(entry.endDate!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AuditSection extends StatelessWidget {
  final ClientProfileState state;
  const _AuditSection({required this.state});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Admin Activity',
      icon: Icons.admin_panel_settings_outlined,
      children: state.auditLogs.asMap().entries.map((entry) {
        return AuditLogTile(
          log: entry.value,
          isLast: entry.key == state.auditLogs.length - 1,
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final ClientProfileState state;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;

  const _ActionButton({
    required this.state,
    required this.onDeactivate,
    required this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isDeactivating) {
      return const Center(child: CircularProgressIndicator());
    }
    final isActive = state.client?.isActive ?? false;
    if (isActive) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: state.isAssigning ? null : onDeactivate,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.statusInactive,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.block_rounded),
          label: const Text('Deactivate Account'),
        ),
      );
    } else {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: state.isAssigning ? null : onReactivate,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Reactivate Account'),
        ),
      );
    }
  }
}

// ── Shared layout widgets ────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoRow(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
