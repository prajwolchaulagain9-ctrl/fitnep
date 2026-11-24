import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes/app_routes.dart';

class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 8,
    children: [
      TextButton(
        key: const Key('terms_link'),
        onPressed: () => context.push(AppRoutes.termsPath),
        child: const Text('Terms and Conditions'),
      ),
      TextButton(
        key: const Key('login_privacy_policy_button'),
        onPressed: () => context.push(AppRoutes.privacyPolicyPath),
        child: const Text('Privacy Policy'),
      ),
    ],
  );
}
