import 'package:flutter/material.dart';

class PasswordFormField extends StatefulWidget {
  const PasswordFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    required this.enabled,
    this.onSubmitted,
    this.autofillHints,
    this.onChanged,
    this.helperText,
  });
  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  @override
  State<PasswordFormField> createState() => _PasswordFormFieldState();
}

class _PasswordFormFieldState extends State<PasswordFormField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    readOnly: !widget.enabled,
    obscureText: _hidden,
    autofillHints: widget.autofillHints,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: widget.onSubmitted == null
        ? TextInputAction.next
        : TextInputAction.done,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helperText,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(
        tooltip: _hidden
            ? 'Show ${widget.label.toLowerCase()}'
            : 'Hide ${widget.label.toLowerCase()}',
        onPressed: widget.enabled
            ? () => setState(() => _hidden = !_hidden)
            : null,
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
    validator: widget.validator,
    onFieldSubmitted: widget.onSubmitted,
    onChanged: widget.onChanged,
  );
}
