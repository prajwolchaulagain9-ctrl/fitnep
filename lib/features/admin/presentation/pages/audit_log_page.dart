import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../controllers/audit_log_controller.dart';
import '../widgets/audit_log_tile.dart';
import '../widgets/empty_state_widget.dart';

class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditLogControllerProvider);
    final controller = ref.read(auditLogControllerProvider.notifier);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Audit Log'),
            Text(
              '${state.logs.length} authorization and admin events recorded',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_rounded),
            tooltip: 'Staff account history',
            onPressed: () => context.push(AppRoutes.adminStaffHistory),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(state.errorMessage!),
              ),
            )
          : state.logs.isEmpty
          ? EmptyStateWidget(
              icon: Icons.history_rounded,
              title: 'No audit logs yet',
              subtitle: 'Administrative actions such as deactivations and profile changes will appear here.',
            )
          : RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerLow,
              onRefresh: controller.refresh,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: state.logs.length,
                itemBuilder: (ctx, index) => AuditLogTile(
                  log: state.logs[index],
                  isLast: index == state.logs.length - 1,
                ),
              ),
            ),
    );
  }
}
