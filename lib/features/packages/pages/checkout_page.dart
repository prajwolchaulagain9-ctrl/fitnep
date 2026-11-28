import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_page.dart';
import '../data/package_repository.dart';
import '../data/payment_models.dart';
import '../membership_controller.dart';
import '../widgets/package_card_header.dart';
import '../widgets/payment_widgets.dart';

final paymentImagePickerProvider = Provider<ImagePicker>(
  (ref) => ImagePicker(),
);

class CheckoutPage extends ConsumerWidget {
  const CheckoutPage({required this.membershipId, super.key});

  final String membershipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(packageAccountProvider).asData?.value;
    final checkout = ref.watch(paymentCheckoutProvider);

    return AppPage(
      title: 'Checkout',
      alignment: Alignment.topCenter,
      child: checkout.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => PackageLoadError(
          message: packageErrorMessage(
            error,
            'We couldn’t load this checkout.',
          ),
          onRetry: () => ref.invalidate(paymentCheckoutProvider),
        ),
        data: (record) =>
            record == null ||
                record.membershipId != membershipId ||
                user == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This checkout is no longer available.'),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.clientMembership),
                    child: const Text('View membership'),
                  ),
                ],
              )
            : _CheckoutForm(
                key: ValueKey((
                  user.uid,
                  record.reference,
                  record.paymentStatus,
                )),
                clientId: user.uid,
                checkout: record,
              ),
      ),
    );
  }
}

class _CheckoutForm extends ConsumerStatefulWidget {
  const _CheckoutForm({
    required this.clientId,
    required this.checkout,
    super.key,
  });

  final String clientId;
  final PackageCheckout checkout;

  @override
  ConsumerState<_CheckoutForm> createState() => _CheckoutFormState();
}

class _CheckoutFormState extends ConsumerState<_CheckoutForm> {
  static const _maxProofBytes = 512 * 1024;
  ({Uint8List bytes, String type, String requestId})? _proof;
  String? _error;
  bool _busy = false;

  Future<void> _pickProof() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final photo = await ref
          .read(paymentImagePickerProvider)
          .pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      if (!mounted || photo == null) return;
      setState(() => _proof = null);
      final length = await photo.length();
      if (length <= 0 || length > _maxProofBytes) {
        throw const PackageFailure('Choose an image up to 512 KB.');
      }
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      final type = _imageType(bytes);
      if (bytes.length > _maxProofBytes || type == null) {
        throw const PackageFailure(
          'Choose a JPEG, PNG or WebP image up to 512 KB.',
        );
      }
      setState(
        () => _proof = (
          bytes: bytes,
          type: type,
          requestId: newPackageRequestId(),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = packageErrorMessage(
            error,
            'We couldn’t open that image.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final proof = _proof;
    if (_busy ||
        proof == null ||
        ref.read(packageAccountProvider).asData?.value?.uid !=
            widget.clientId) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payment = await ref
          .read(packageRepositoryProvider)
          .submitProof(
            membershipId: widget.checkout.membershipId,
            clientId: widget.clientId,
            reference: widget.checkout.reference,
            requestId: proof.requestId,
            bytes: proof.bytes,
            contentType: proof.type,
          );
      if (!mounted) return;
      ref.invalidate(paymentCheckoutProvider);
      ref.invalidate(paymentHistoryProvider);
      ref.invalidate(packageMembershipsProvider);
      ref.invalidate(membershipControllerProvider);
      context.pushReplacementNamed(
        AppRoutes.paymentDetailsName,
        pathParameters: {'id': payment.id},
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = packageErrorMessage(
            error,
            'We couldn’t submit your proof. Try again.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final checkout = widget.checkout;
    final pending = checkout.paymentStatus == PaymentStatus.pending;
    final replacing = checkout.paymentStatus == PaymentStatus.rejected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PackageCardHeader(
          packageName: checkout.package.name,
          subtitle: Text(checkout.package.durationLabel),
        ),
        const SizedBox(height: 16),
        Text('Full package price', style: theme.textTheme.labelLarge),
        Text(
          packagePrice(checkout.amountNpr),
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        PaymentReference(
          reference: checkout.reference,
          qrPayload: checkout.qrPayload,
        ),
        const SizedBox(height: 20),
        if (pending) ...[
          Text('Awaiting verification', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Your proof was submitted. An administrator will review it before your package is confirmed.',
          ),
          const SizedBox(height: 12),
          if (checkout.paymentId case final id?)
            FilledButton(
              onPressed: () => context.pushNamed(
                AppRoutes.paymentDetailsName,
                pathParameters: {'id': id},
              ),
              child: const Text('View payment status'),
            ),
          TextButton(
            onPressed: () => ref.invalidate(paymentCheckoutProvider),
            child: const Text('Refresh checkout'),
          ),
        ] else ...[
          Text(
            replacing ? 'Replace rejected proof' : 'Payment proof',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            replacing
                ? 'Choose a new test proof image for the updated reference. JPEG, PNG or WebP up to 512 KB.'
                : 'Choose a test proof image to continue. JPEG, PNG or WebP up to 512 KB.',
          ),
          if (replacing && checkout.paymentId != null)
            TextButton(
              onPressed: () => context.pushNamed(
                AppRoutes.paymentDetailsName,
                pathParameters: {'id': checkout.paymentId!},
              ),
              child: const Text('View rejection reason'),
            ),
          const SizedBox(height: 12),
          if (_proof case final proof?) ...[
            Image.memory(
              proof.bytes,
              height: 136,
              fit: BoxFit.contain,
              semanticLabel: 'Selected proof image',
              errorBuilder: (context, error, stack) =>
                  const Text('The image preview is unavailable.'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickProof,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              _proof == null ? 'Choose proof image' : 'Change proof image',
            ),
          ),
          if (_error != null) PackageLoadError(message: _error!),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || _proof == null ? null : _submit,
            child: const Text('Submit proof for review'),
          ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

String? _imageType(Uint8List bytes) {
  bool matches(List<int> header, [int offset = 0]) {
    if (bytes.length < header.length + offset) return false;
    for (var index = 0; index < header.length; index++) {
      if (bytes[index + offset] != header[index]) return false;
    }
    return true;
  }

  if (matches(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (matches(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (matches(const [0x52, 0x49, 0x46, 0x46]) &&
      matches(const [0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  return null;
}
