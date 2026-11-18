import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/datasources/notification_destination_remote_datasource.dart';
import '../../domain/entities/notification_destination_record.dart';
import '../../domain/entities/notification_entity.dart';
import '../controllers/notification_destination_controller.dart';

class NotificationDestinationPage extends ConsumerWidget {
  final NotificationType type;
  final String referenceId;

  const NotificationDestinationPage({
    super.key,
    required this.type,
    required this.referenceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = NotificationDestinationRequest(
      type: type,
      referenceId: referenceId,
    );
    final state = ref.watch(notificationDestinationProvider(request));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_pageTitle)),
      body: SafeArea(
        top: false,
        child: state.when(
          data: (record) => _RecordView(
            type: type,
            record: record,
            onRefresh: () async {
              ref.invalidate(notificationDestinationProvider(request));
              await ref.read(notificationDestinationProvider(request).future);
            },
          ),
          error: (error, _) => _DestinationErrorView(
            error: error,
            onRetry: () =>
                ref.invalidate(notificationDestinationProvider(request)),
            onBack: () => Navigator.of(context).maybePop(),
          ),
          loading: () => _DestinationLoadingView(label: _recordLabel),
        ),
      ),
    );
  }

  String get _pageTitle => switch (type) {
    NotificationType.dietPlan => 'Diet Plan Details',
    NotificationType.message => 'Messages',
    NotificationType.task => 'Task Details',
    NotificationType.payment => 'Payment Details',
    NotificationType.other => 'Details',
  };

  String get _recordLabel => switch (type) {
    NotificationType.dietPlan => 'diet plan',
    NotificationType.message => 'conversation',
    NotificationType.task => 'task',
    NotificationType.payment => 'payment',
    NotificationType.other => 'record',
  };
}

class _RecordView extends StatelessWidget {
  final NotificationType type;
  final NotificationDestinationRecord record;
  final Future<void> Function() onRefresh;

  const _RecordView({
    required this.type,
    required this.record,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(_icon, color: _accent, size: 27),
                ),
                const SizedBox(height: 18),
                Text(
                  record.title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(height: 1.3),
                ),
                if (record.description != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    record.description!,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(height: 1.5),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Reference: ${record.id}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (record.fields.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < record.fields.length;
                    index++
                  ) ...[
                    _DetailRow(field: record.fields[index]),
                    if (index < record.fields.length - 1)
                      const Divider(indent: 16, endIndent: 16),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData get _icon => switch (type) {
    NotificationType.dietPlan => Icons.restaurant_menu_rounded,
    NotificationType.message => Icons.forum_outlined,
    NotificationType.task => Icons.task_alt_rounded,
    NotificationType.payment => Icons.receipt_long_outlined,
    NotificationType.other => Icons.description_outlined,
  };

  Color get _accent => switch (type) {
    NotificationType.dietPlan => AppColors.success,
    NotificationType.message => AppColors.info,
    NotificationType.task => AppColors.actionPackageChange,
    NotificationType.payment => AppColors.warning,
    NotificationType.other => AppColors.primary,
  };
}

class _DetailRow extends StatelessWidget {
  final NotificationDestinationField field;

  const _DetailRow({required this.field});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              field.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              field.value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationLoadingView extends StatelessWidget {
  final String label;

  const _DestinationLoadingView({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Loading $label...'),
        ],
      ),
    );
  }
}

class _DestinationErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _DestinationErrorView({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final destinationError = error is NotificationDestinationException
        ? error as NotificationDestinationException
        : null;
    final canRetry = destinationError?.canRetry ?? true;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon(destinationError?.failure),
                color: AppColors.error,
                size: 38,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _title(destinationError?.failure),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 24),
            if (canRetry)
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
              )
            else
              OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Go Back'),
              ),
          ],
        ),
      ),
    );
  }

  String _title(NotificationDestinationFailure? failure) => switch (failure) {
    NotificationDestinationFailure.notFound => 'Record not found',
    NotificationDestinationFailure.forbidden => 'Access denied',
    NotificationDestinationFailure.unauthorized => 'Session expired',
    NotificationDestinationFailure.invalidReference => 'Invalid notification',
    _ => 'Could not load details',
  };

  IconData _icon(NotificationDestinationFailure? failure) => switch (failure) {
    NotificationDestinationFailure.notFound => Icons.search_off_rounded,
    NotificationDestinationFailure.forbidden => Icons.lock_outline_rounded,
    NotificationDestinationFailure.unauthorized => Icons.login_rounded,
    NotificationDestinationFailure.network => Icons.wifi_off_rounded,
    _ => Icons.error_outline_rounded,
  };
}
