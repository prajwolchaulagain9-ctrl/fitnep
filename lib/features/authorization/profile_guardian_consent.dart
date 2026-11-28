import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_routes.dart';

Future<bool> showProfileGuardianConsent(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Parent or guardian consent'),
        content: const Text(
          'Ask a parent or guardian to review the Privacy Policy and confirm '
          'that you have permission to provide your health information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          if (GoRouter.maybeOf(context) != null)
            TextButton(
              onPressed: () => context.pushNamed(AppRoutes.privacyPolicy),
              child: const Text('Read privacy policy'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm permission'),
          ),
        ],
      ),
    ) ==
    true;
