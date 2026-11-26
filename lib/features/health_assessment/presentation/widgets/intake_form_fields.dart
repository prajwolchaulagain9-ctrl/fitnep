import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/client_intake_form.dart';

class IntakeFormFields extends StatelessWidget {
  const IntakeFormFields({
    super.key,
    required this.controllers,
    required this.enabled,
    required this.onChanged,
    required this.validator,
  });

  final Map<IntakeField, TextEditingController> controllers;
  final bool enabled;
  final ValueChanged<IntakeField> onChanged;
  final String? Function(IntakeField) validator;

  @override
  Widget build(BuildContext context) {
    final bmi = intakeBmi(
      controllers[IntakeField.height]!.text.trim(),
      controllers[IntakeField.weight]!.text.trim(),
    );
    final sections = <(String, List<IntakeField>)>[
      (
        'Personal and contact details',
        [
          IntakeField.fullName,
          IntakeField.age,
          IntakeField.dateOfBirth,
          IntakeField.email,
          IntakeField.phone,
        ],
      ),
      (
        'Measurements',
        [
          IntakeField.height,
          IntakeField.weight,
          IntakeField.waist,
          IntakeField.hip,
          IntakeField.chest,
        ],
      ),
      (
        'Goals and health information',
        [IntakeField.goals, IntakeField.medicalHistory],
      ),
      (
        'Food and dietary information',
        [
          IntakeField.allergies,
          IntakeField.restrictions,
          IntakeField.foodPreferences,
        ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, fields) in sections) ...[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final field in fields)
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
          if (bmi != null && fields.contains(IntakeField.height))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'BMI estimate: ${bmi.toStringAsFixed(1)} kg/m²',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 12),
        ],
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
      IntakeField.age => TextInputType.number,
      IntakeField.email => TextInputType.emailAddress,
      IntakeField.phone => TextInputType.phone,
      IntakeField.dateOfBirth => TextInputType.datetime,
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
      inputFormatters: field == IntakeField.age
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field == IntakeField.dateOfBirth ? 'YYYY-MM-DD' : null,
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
