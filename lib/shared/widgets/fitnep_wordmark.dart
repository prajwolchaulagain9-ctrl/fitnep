import 'package:flutter/material.dart';

// Text branding until the original Figma logo export is supplied.
class FitNepWordmark extends StatelessWidget {
  const FitNepWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'FitNEP',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
