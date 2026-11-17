import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/client_entity.dart';
import '../../../../app/theme/app_theme.dart';

class PaymentHistoryTile extends StatelessWidget {
  final PaymentHistoryEntry payment;
  final bool isLast;

  const PaymentHistoryTile({
    super.key,
    required this.payment,
    this.isLast = false,
  });

  Color get _statusColor {
    switch (payment.status) {
      case PaymentStatus.paid:
        return AppColors.statusActive;
      case PaymentStatus.pending:
        return AppColors.statusPending;
      case PaymentStatus.overdue:
        return AppColors.statusInactive;
    }
  }

  Color get _statusBg {
    switch (payment.status) {
      case PaymentStatus.paid:
        return AppColors.statusActiveContainer;
      case PaymentStatus.pending:
        return AppColors.statusPendingContainer;
      case PaymentStatus.overdue:
        return AppColors.statusInactiveContainer;
    }
  }

  String get _statusLabel {
    switch (payment.status) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.overdue:
        return 'Overdue';
    }
  }

  IconData get _statusIcon {
    switch (payment.status) {
      case PaymentStatus.paid:
        return Icons.check_circle_outline_rounded;
      case PaymentStatus.pending:
        return Icons.schedule_rounded;
      case PaymentStatus.overdue:
        return Icons.warning_amber_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Timeline dot + line
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 1.5,
                  height: 44,
                  color: AppColors.divider,
                ),
            ],
          ),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment.description,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        DateFormat('dd MMM yyyy').format(payment.date),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Rs. ${payment.amount.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusBg,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon,
                              size: 10, color: _statusColor),
                          const SizedBox(width: 3),
                          Text(
                            _statusLabel,
                            style: TextStyle(
                              color: _statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
