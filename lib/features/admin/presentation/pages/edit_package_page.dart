import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/entities/package_entity.dart';
import '../controllers/package_management_controller.dart';

class EditPackagePage extends ConsumerStatefulWidget {
  /// The package to edit, passed as route extra.
  final PackageEntity package;

  const EditPackagePage({super.key, required this.package});

  @override
  ConsumerState<EditPackagePage> createState() => _EditPackagePageState();
}

class _EditPackagePageState extends ConsumerState<EditPackagePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _durationController;
  late final TextEditingController _priceController;
  late final TextEditingController _featureController;

  bool _submitting = false;
  String? _submitError;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.package.name);
    _durationController =
        TextEditingController(text: widget.package.durationMonths.toString());
    _priceController = TextEditingController(
      text: widget.package.price % 1 == 0
          ? widget.package.price.toInt().toString()
          : widget.package.price.toString(),
    );
    _featureController =
        TextEditingController(text: widget.package.featureDescription);

    for (final c in [
      _nameController,
      _durationController,
      _priceController,
      _featureController,
    ]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _priceController.dispose();
    _featureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty || _submitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmDiscard(context);
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Edit Package')),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                24 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                TextFormField(
                  key: const Key('edit_package_name_field'),
                  controller: _nameController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Package name',
                    hintText: 'e.g. Premium Fitness',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: _validateName,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('edit_package_duration_field'),
                  controller: _durationController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Duration (months)',
                    hintText: 'e.g. 3',
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  validator: _validateDuration,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('edit_package_price_field'),
                  controller: _priceController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Price (NPR)',
                    hintText: 'e.g. 2500',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: _validatePrice,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('edit_package_feature_field'),
                  controller: _featureController,
                  enabled: !_submitting,
                  minLines: 4,
                  maxLines: 7,
                  maxLength: 1000,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Feature description',
                    hintText: 'Describe what customers receive in this package.',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 72),
                      child: Icon(Icons.checklist_rounded),
                    ),
                  ),
                  validator: _validateFeature,
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 4),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.statusInactiveContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _submitError!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  key: const Key('edit_package_submit'),
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textInverse,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _submitting ? 'Saving changes...' : 'Save changes',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final updated = await ref
          .read(packageManagementControllerProvider.notifier)
          .updatePackage(
            id: widget.package.id,
            name: _nameController.text.trim(),
            durationMonths: int.parse(_durationController.text.trim()),
            price: double.parse(_priceController.text.trim()),
            featureDescription: _featureController.text.trim(),
          );
      if (mounted) context.pop(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = error.toString();
      });
    }
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Your unsaved edits will be lost if you go back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Discard',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  String? _validateName(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Package name is required.';
    if (text.length > 100) return 'Use 100 characters or fewer.';
    return null;
  }

  String? _validateDuration(String? value) {
    final duration = int.tryParse(value?.trim() ?? '');
    if (duration == null || duration <= 0) {
      return 'Enter a positive whole number of months.';
    }
    if (duration > 120) return 'Duration cannot exceed 120 months.';
    return null;
  }

  String? _validatePrice(String? value) {
    final price = double.tryParse(value?.trim() ?? '');
    if (price == null || !price.isFinite || price <= 0) {
      return 'Enter a valid positive price.';
    }
    if (price > 100000000) return 'Price is too large.';
    return null;
  }

  String? _validateFeature(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Feature description is required.';
    if (text.length > 1000) return 'Use 1000 characters or fewer.';
    return null;
  }
}
