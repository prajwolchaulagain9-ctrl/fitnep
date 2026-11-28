import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_page.dart';
import '../data/package_repository.dart';
import '../data/payment_models.dart';
import '../widgets/payment_widgets.dart';

class PackageApprovalsPage extends ConsumerStatefulWidget {
  const PackageApprovalsPage({super.key});

  @override
  ConsumerState<PackageApprovalsPage> createState() =>
      _PackageApprovalsPageState();
}

class _PackageApprovalsPageState extends ConsumerState<PackageApprovalsPage> {
  PaymentStatus _status = PaymentStatus.pending;

  @override
  Widget build(BuildContext context) {
    final queue = paymentReviewQueueProvider(_status);
    final records = ref.watch(queue);
    return AppPage(
      title: 'Payment review',
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final status in PaymentStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: status == _status,
                  onSelected: (_) => setState(() => _status = status),
                ),
              IconButton(
                tooltip: 'Refresh payments',
                onPressed: () => ref.invalidate(queue),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          records.when(
            skipLoadingOnRefresh: false,
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => PackageLoadError(
              message: packageErrorMessage(
                error,
                'We couldn’t load these payments.',
              ),
              onRetry: () => ref.invalidate(queue),
            ),
            data: (items) => items.isEmpty
                ? Text(switch (_status) {
                    PaymentStatus.pending =>
                      'No payments are awaiting verification.',
                    PaymentStatus.verified => 'No payments have been verified.',
                    PaymentStatus.rejected => 'No payments have been rejected.',
                  })
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in items)
                        PaymentListTile(payment: item, review: true),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
