import 'package:flutter/material.dart';

import '../../../authorization/domain/profile_age.dart';
import '../../../authorization/presentation/profile_guardian_consent.dart';

typedef IntakeBirthDateDetails = ({String date, bool guardianConfirmed});

class IntakeBirthDateDialog extends StatefulWidget {
  const IntakeBirthDateDialog({
    required this.initialDate,
    required this.guardianConfirmed,
    super.key,
  });

  final String initialDate;
  final bool guardianConfirmed;

  @override
  State<IntakeBirthDateDialog> createState() => _IntakeBirthDateDialogState();
}

class _IntakeBirthDateDialogState extends State<IntakeBirthDateDialog> {
  final _form = GlobalKey<FormState>();
  late final _birthDate = TextEditingController(text: widget.initialDate);
  bool _confirming = false;

  @override
  void dispose() {
    _birthDate.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_confirming || !_form.currentState!.validate()) return;
    final date = _birthDate.text.trim();
    final isMinor = ageFromBirthDate(date, DateTime.now())! < 18;
    var guardianConfirmed = widget.guardianConfirmed;
    if (isMinor && !guardianConfirmed) {
      FocusScope.of(context).unfocus();
      setState(() => _confirming = true);
      guardianConfirmed = await showProfileGuardianConsent(context);
      if (!mounted) return;
      setState(() => _confirming = false);
      if (!guardianConfirmed) return;
    }
    Navigator.of(context)
        .pop((date: date, guardianConfirmed: guardianConfirmed));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirm your date of birth'),
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('We’ll save this in My profile.'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _birthDate,
            autofocus: true,
            enabled: !_confirming,
            keyboardType: TextInputType.datetime,
            textInputAction: TextInputAction.done,
            maxLength: 10,
            decoration: const InputDecoration(
              labelText: 'Date of birth',
              hintText: 'YYYY-MM-DD',
              counterText: '',
            ),
            validator: (value) =>
                ageFromBirthDate(value?.trim() ?? '', DateTime.now()) == null
                ? 'Enter a valid date of birth.'
                : null,
            onFieldSubmitted: (_) => _continue(),
          ),
        ],
      ),
    ),
    scrollable: true,
    actions: [
      TextButton(
        onPressed: _confirming ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _confirming ? null : _continue,
        child: const Text('Save and continue'),
      ),
    ],
  );
}
