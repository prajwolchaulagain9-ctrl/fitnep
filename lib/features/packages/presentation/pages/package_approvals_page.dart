import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../core/config/app_config.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../data/package_repository.dart';
import '../../domain/package_models.dart';

class _VerificationDialog extends StatefulWidget {
  const _VerificationDialog({required this.initialReference});
  final String initialReference;
  @override
  State<_VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends State<_VerificationDialog> {
  final _form = GlobalKey<FormState>();
  late final _reference = TextEditingController(text: widget.initialReference);
  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Verify this payment?'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppConfig.useFirebaseEmulators
                ? 'This approves a test payment. No money is charged.'
                : 'Confirm the payment has been checked before activating this package.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _reference,
            decoration: const InputDecoration(
              labelText: 'Verification reference',
            ),
            maxLength: 200,
            validator: (value) => (value?.trim().length ?? 0) < 3
                ? 'Enter a payment record or receipt reference.'
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reference.text.trim());
          }
        },
        child: const Text('Verify and activate'),
      ),
    ],
  );
}

class PackageApprovalsPage extends ConsumerStatefulWidget {
  const PackageApprovalsPage({super.key});
  @override
  ConsumerState<PackageApprovalsPage> createState() =>
      _PackageApprovalsPageState();
}

class _PackageApprovalsPageState extends ConsumerState<PackageApprovalsPage> {
  String? _busyId;
  String? _error;

  Future<void> _verify(PackageMembership member) async {
    if (_busyId != null) return;
    setState(() => _busyId = member.id);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (context) => _VerificationDialog(
        initialReference: AppConfig.useFirebaseEmulators
            ? 'DEMO-${member.id.substring(0, 8)}'
            : '',
      ),
    );
    if (!mounted) return;
    if (confirmed == null) {
      setState(() => _busyId = null);
      return;
    }
    setState(() => _error = null);
    try {
      await ref
          .read(packageRepositoryProvider)
          .verifyPayment(member.id, confirmed);
      if (!mounted) return;
      ref.invalidate(pendingPackageApprovalsProvider);
      ref.invalidate(packageMembershipsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment verified. Package activated.')),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PackageFailure
              ? error.message
              : 'We couldn’t verify this payment. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(pendingPackageApprovalsProvider);
    return AppPage(
      title: 'Package approvals',
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Review pending packages',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            AppConfig.useFirebaseEmulators
                ? 'Approve a test payment to complete the demo. No real money is processed.'
                : 'Manually verify payments to activate a client’s package.',
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.push(AppRoutes.adminStaffAccounts),
            child: const Text('Manage staff accounts'),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          records.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error is PackageFailure
                      ? error.message
                      : 'We couldn’t load pending packages.',
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(pendingPackageApprovalsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No packages are awaiting verification.'),
                  )
                : Column(
                    children: [
                      for (final member in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    member.package.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    member.clientId == 'demo-client'
                                        ? 'Demo Client'
                                        : 'Client: ${member.clientId}',
                                  ),
                                  Text(
                                    'Rs. ${NumberFormat('#,##0.##').format(member.package.priceNpr)} · ${member.package.durationLabel}',
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: _busyId == null
                                        ? () => _verify(member)
                                        : null,
                                    child: Text(
                                      _busyId == member.id
                                          ? 'Verifying…'
                                          : 'Review payment',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
