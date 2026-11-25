import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

Future<String?> showDeactivationDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (ctx) => const _DeactivationDialog(),
  );
}

class _DeactivationDialog extends StatefulWidget {
  const _DeactivationDialog();

  @override
  State<_DeactivationDialog> createState() => _DeactivationDialogState();
}

class _DeactivationDialogState extends State<_DeactivationDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.statusInactiveContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: AppColors.statusInactive,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Deactivate Account',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'This will not delete the account.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 20),

              // Warning notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusInactiveContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.statusInactive.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.statusInactive,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All client data, payment records and history will be preserved. '
                        'The client will lose access to the app.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.statusInactive,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Reason field
              Text(
                'Reason for deactivation *',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _controller,
                maxLines: 3,
                maxLength: 300,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText:
                      'e.g. Non-payment, violation of terms, client request...',
                  counterStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please provide a reason for deactivation.';
                  }
                  if (v.trim().length < 10) {
                    return 'Reason must be at least 10 characters.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusInactive,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _hasText
                          ? () {
                              if (_formKey.currentState!.validate()) {
                                Navigator.of(context)
                                    .pop(_controller.text.trim());
                              }
                            }
                          : null,
                      child: const Text('Deactivate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
