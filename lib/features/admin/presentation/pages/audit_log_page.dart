import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/audit_log_controller.dart';
import '../widgets/audit_log_tile.dart';
import '../widgets/empty_state_widget.dart';
import '../../../../app/theme/app_theme.dart';

class AuditLogPage extends ConsumerWidget {
  const AuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditLogControllerProvider);
    final controller = ref.read(auditLogControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Audit Log'),
            Text(
              '${state.logs.length} admin actions recorded',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: controller.refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.logs.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.history_rounded,
                  title: 'No audit logs yet',
                  subtitle:
                      'Administrative actions such as deactivations and profile changes will appear here.',
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceElevated,
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
