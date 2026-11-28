import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/routes/route_access_gate.dart';
import '../../../shared/widgets/app_page.dart';
import '../../admin/client_list_controller.dart';
import '../../admin/client_profile_controller.dart';
import '../../notifications/data/notification_entity.dart';
import '../../notifications/pages/notification_destination_page.dart';
import '../data/package_repository.dart';
import '../data/payment_models.dart';
import '../membership_controller.dart';
import '../widgets/package_card_header.dart';
import '../widgets/payment_widgets.dart';

class PaymentDetailsPage extends ConsumerWidget {
  const PaymentDetailsPage({required this.paymentId, super.key});

  final String paymentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(routeSessionProvider).asData?.value;
    final details = ref.watch(paymentDetailsProvider(paymentId));
    if (details.asData case AsyncData(value: null)) {
      return NotificationDestinationPage(
        type: NotificationType.payment,
        referenceId: paymentId,
      );
    }
    return AppPage(
      title: 'Payment details',
      alignment: Alignment.topCenter,
      child: details.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => PackageLoadError(
          message: packageErrorMessage(error, 'We couldn’t load this payment.'),
          onRetry: () => ref.invalidate(paymentDetailsProvider(paymentId)),
        ),
        data: (record) => _PaymentRecord(
          key: ValueKey((
            session?.uid,
            record!.payment.id,
            record.payment.revision,
          )),
          details: record,
          canReview:
              session?.authorization.hasPermission('verify_payments') == true,
          canAdjust: session?.role == FitNepRole.admin,
        ),
      ),
    );
  }
}

class _PaymentRecord extends ConsumerStatefulWidget {
  const _PaymentRecord({
    required this.details,
    required this.canReview,
    required this.canAdjust,
    super.key,
  });

  final PaymentDetails details;
  final bool canReview;
  final bool canAdjust;

  @override
  ConsumerState<_PaymentRecord> createState() => _PaymentRecordState();
}

class _PaymentRecordState extends ConsumerState<_PaymentRecord> {
  PackagePayment get _payment => widget.details.payment;
  Uint8List? _viewableProof;
  bool _proofChecked = false;
  bool _busy = false;
  bool _saving = false;
  String? _error;
  ({num? amount, String reason})? _adjustmentDraft;
  String? _adjustmentRequestId;

  Future<void> _decide({required bool reject}) async {
    if (_busy || !widget.canReview || (!reject && !_proofChecked)) return;
    setState(() => _busy = true);
    final decision = reject
        ? await showDialog<({num? amount, String reason})>(
            context: context,
            builder: (_) => const _PaymentReasonDialog(adjustment: false),
          )
        : null;
    if (!mounted) return;
    if ((reject && decision == null) || !widget.canReview) {
      setState(() => _busy = false);
      return;
    }
    await _save(() async {
      await ref
          .read(packageRepositoryProvider)
          .reviewPayment(_payment, reason: decision?.reason);
    });
  }

  Future<void> _adjust() async {
    if (_busy || !widget.canAdjust) return;
    setState(() => _busy = true);
    final draft = await showDialog<({num? amount, String reason})>(
      context: context,
      builder: (_) =>
          _PaymentReasonDialog(adjustment: true, initial: _adjustmentDraft),
    );
    if (!mounted) return;
    if (draft == null || !widget.canAdjust) {
      setState(() => _busy = false);
      return;
    }
    if (_adjustmentDraft != draft) {
      _adjustmentDraft = draft;
      _adjustmentRequestId = newPackageRequestId();
    }
    await _save(() async {
      await ref
          .read(packageRepositoryProvider)
          .addAdjustment(
            paymentId: _payment.id,
            reason: draft.reason,
            amountDeltaNpr: draft.amount!,
            requestId: _adjustmentRequestId!,
          );
      _adjustmentDraft = null;
      _adjustmentRequestId = null;
    });
  }

  Future<void> _save(Future<void> Function() operation) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await operation();
      if (!mounted) return;
      ref.invalidate(paymentDetailsProvider(_payment.id));
      ref.invalidate(paymentReviewQueueProvider);
      ref.invalidate(paymentHistoryProvider);
      ref.invalidate(packageMembershipsProvider);
      ref.invalidate(paymentCheckoutProvider);
      ref.invalidate(membershipControllerProvider);
      if (widget.canReview) {
        ref.invalidate(clientListControllerProvider);
        ref.invalidate(clientProfileControllerProvider);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = packageErrorMessage(
            error,
            'We couldn’t save this change. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final payment = _payment;
    final theme = Theme.of(context);
    final proofProvider = paymentProofProvider(payment.id);
    final proof = ref.watch(proofProvider);
    final proofDisplayed =
        _viewableProof != null &&
        identical(_viewableProof, proof.asData?.value);
    final canApprove =
        widget.canReview && payment.status == PaymentStatus.pending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PackageCardHeader(
          packageName: payment.package.name,
          subtitle: Text(payment.package.durationLabel),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                packagePrice(payment.amountNpr),
                style: theme.textTheme.headlineMedium,
              ),
            ),
            Chip(label: Text(payment.status.label)),
            IconButton(
              tooltip: 'Refresh payment',
              onPressed: _busy
                  ? null
                  : () {
                      ref.invalidate(proofProvider);
                      ref.invalidate(paymentDetailsProvider(payment.id));
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (widget.canReview)
          Text(payment.clientName, style: theme.textTheme.titleMedium),
        Text('Submitted ${paymentDate(payment.createdAt)} (Nepal time)'),
        if (payment.reviewedAt case final date?)
          Text('Reviewed ${paymentDate(date)} (Nepal time)'),
        if (payment.reviewedByName case final name?) Text('Reviewed by $name'),
        if (payment.status == PaymentStatus.pending && !widget.canReview) ...[
          const SizedBox(height: 8),
          const Text(
            'Your proof is awaiting review. You can choose another package once this payment is verified.',
          ),
        ],
        if (payment.rejectionReason case final reason?) ...[
          const SizedBox(height: 12),
          Text('Rejection reason', style: theme.textTheme.titleMedium),
          Text(reason),
          if (!widget.canReview)
            TextButton(
              onPressed: () => context.pushNamed(
                AppRoutes.clientCheckoutName,
                pathParameters: {'membershipId': payment.membershipId},
              ),
              child: const Text('Open checkout'),
            ),
        ],
        const SizedBox(height: 16),
        PaymentReference(
          reference: payment.reference,
          qrPayload: payment.qrPayload,
        ),
        const SizedBox(height: 20),
        Text('Submitted proof', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        proof.when(
          skipLoadingOnRefresh: false,
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => PackageLoadError(
            message: packageErrorMessage(
              error,
              'We couldn’t load the proof image.',
            ),
            onRetry: () => ref.invalidate(proofProvider),
          ),
          data: (bytes) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              semanticLabel: 'Submitted payment proof',
              frameBuilder: (context, child, frame, synchronouslyLoaded) {
                if (canApprove &&
                    frame != null &&
                    !identical(_viewableProof, bytes)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || identical(_viewableProof, bytes)) return;
                    setState(() {
                      _viewableProof = bytes;
                      _proofChecked = false;
                    });
                  });
                }
                return child;
              },
              errorBuilder: (context, error, stack) =>
                  const Text('The proof image could not be displayed.'),
            ),
          ),
        ),
        if (canApprove) ...[
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _proofChecked && proofDisplayed,
            onChanged: _busy || !proofDisplayed
                ? null
                : (checked) => setState(() => _proofChecked = checked == true),
            title: const Text(
              'I checked the QR, submitted proof and selected package.',
            ),
          ),
          FilledButton(
            onPressed: _busy || !_proofChecked || !proofDisplayed
                ? null
                : () => _decide(reject: false),
            child: const Text('Verify payment'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _decide(reject: true),
            child: const Text('Reject payment'),
          ),
        ],
        if (payment.status == PaymentStatus.verified &&
            (widget.canAdjust || widget.details.adjustments.isNotEmpty)) ...[
          const SizedBox(height: 24),
          Text('Payment adjustments', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final adjustment in widget.details.adjustments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${adjustment.amountDeltaNpr > 0 ? '+' : '−'}${packagePrice(adjustment.amountDeltaNpr.abs())}',
              ),
              subtitle: Text(
                [
                  adjustment.reason,
                  '${paymentDate(adjustment.createdAt)} (Nepal time)',
                  ?adjustment.createdByName,
                ].join('\n'),
              ),
            ),
          if (widget.canAdjust) ...[
            const Text(
              'Add a logged correction. This does not send a charge or refund.',
            ),
            OutlinedButton(
              onPressed: _busy ? null : _adjust,
              child: const Text('Log adjustment'),
            ),
          ],
        ],
        if (_saving) const LinearProgressIndicator(),
        if (_error != null) PackageLoadError(message: _error!),
      ],
    );
  }
}

class _PaymentReasonDialog extends StatefulWidget {
  const _PaymentReasonDialog({required this.adjustment, this.initial});

  final bool adjustment;
  final ({num? amount, String reason})? initial;

  @override
  State<_PaymentReasonDialog> createState() => _PaymentReasonDialogState();
}

class _PaymentReasonDialogState extends State<_PaymentReasonDialog> {
  final _form = GlobalKey<FormState>();
  late final _reason = TextEditingController(text: widget.initial?.reason);
  late final _amount = TextEditingController(
    text: widget.initial?.amount?.toString(),
  );

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.adjustment ? 'Log a payment adjustment' : 'Reject this payment?',
    ),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.adjustment) ...[
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount change in NPR',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                final amount = num.tryParse(text);
                return amount == null ||
                        !amount.isFinite ||
                        amount == 0 ||
                        amount.abs() > 1000000000 ||
                        !RegExp(r'^[+-]?\d+(\.\d{1,2})?$').hasMatch(text)
                    ? 'Enter a non-zero amount up to NPR 1 billion with at most two decimal places.'
                    : null;
              },
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            maxLength: 400,
            maxLines: 3,
            validator: (value) =>
                value?.trim().isNotEmpty == true ? null : 'Enter a reason.',
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
            Navigator.pop(context, (
              amount: widget.adjustment ? num.parse(_amount.text.trim()) : null,
              reason: _reason.text.trim(),
            ));
          }
        },
        child: Text(
          widget.adjustment ? 'Save adjustment' : 'Confirm rejection',
        ),
      ),
    ],
  );
}
