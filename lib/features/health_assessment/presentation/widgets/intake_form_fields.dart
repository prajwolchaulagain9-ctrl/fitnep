import 'package:flutter/material.dart';

import '../../domain/entities/client_intake_form.dart';

class IntakeFormFields extends StatelessWidget {
  const IntakeFormFields({
    super.key,
    required this.controllers,
    required this.step,
    required this.enabled,
    required this.onChanged,
    required this.validator,
  });

  final Map<IntakeField, TextEditingController> controllers;
  final IntakeStep step;
  final bool enabled;
  final ValueChanged<IntakeField> onChanged;
  final String? Function(IntakeField) validator;

  @override
  Widget build(BuildContext context) {
    final bmi = intakeBmi(
      controllers[IntakeField.height]!.text.trim(),
      controllers[IntakeField.weight]!.text.trim(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in step.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _IntakeInput(
              field: field,
              controller: controllers[field]!,
              enabled: enabled,
              onChanged: () => onChanged(field),
              validator: () => validator(field),
            ),
          ),
        if (step == IntakeStep.measurements)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.speed_rounded),
              iconColor: Theme.of(context).colorScheme.onSecondaryContainer,
              textColor: Theme.of(context).colorScheme.onSecondaryContainer,
              title: const Text('BMI estimate'),
              subtitle: Text(
                bmi == null
                    ? 'Enter your height and weight to see your estimate.'
                    : '${bmi.toStringAsFixed(1)} kg/m²',
              ),
            ),
          ),
      ],
    );
  }
}

class _IntakeInput extends StatelessWidget {
  const _IntakeInput({
    required this.field,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.validator,
  });

  final IntakeField field;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final String? Function() validator;

  bool get _allowsNone => const {
    IntakeField.medicalHistory,
    IntakeField.allergies,
    IntakeField.restrictions,
  }.contains(field);

  @override
  Widget build(BuildContext context) {
    final multiline = field.maxLength == 1000;
    final keyboard = switch (field) {
      _ when field.range != null => const TextInputType.numberWithOptions(
        decimal: true,
      ),
      _ => multiline ? TextInputType.multiline : TextInputType.text,
    };
    return TextFormField(
      key: ValueKey(field.key),
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      textInputAction: multiline
          ? TextInputAction.newline
          : TextInputAction.next,
      minLines: multiline ? 2 : 1,
      maxLines: multiline ? 4 : 1,
      maxLength: field.maxLength,
      decoration: InputDecoration(
        labelText: field.label,
        prefixIcon: Icon(switch (field) {
          IntakeField.height => Icons.height_rounded,
          IntakeField.weight => Icons.monitor_weight_outlined,
          IntakeField.waist ||
          IntakeField.hip ||
          IntakeField.chest => Icons.straighten_rounded,
          IntakeField.goals => Icons.flag_outlined,
          IntakeField.medicalHistory => Icons.medical_information_outlined,
          IntakeField.allergies => Icons.warning_amber_rounded,
          IntakeField.restrictions => Icons.no_food_outlined,
          IntakeField.foodPreferences => Icons.restaurant_menu_rounded,
        }),
        helperText: _allowsNone ? 'Enter None if this does not apply.' : null,
        counterText: '',
        suffixIcon: _allowsNone
            ? TextButton(
                onPressed: enabled
                    ? () {
                        controller.text = 'None';
                        onChanged();
                      }
                    : null,
                child: const Text('None'),
              )
            : null,
      ),
      onChanged: (_) => onChanged(),
      validator: (_) => validator(),
    );
  }
}
