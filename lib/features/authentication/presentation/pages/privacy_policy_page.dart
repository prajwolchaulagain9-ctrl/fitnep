import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_page.dart';
import '../../domain/entities/privacy_policy.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPage(
      title: 'Privacy Policy',
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How FitNEP handles your data',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Version $privacyPolicyVersion'),
          const SizedBox(height: 24),
          for (final (title, detail) in _sections) ...[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(detail),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

const _sections = [
  (
    'Account and consent',
    'FitNEP uses your name and email to create your account. We ask for your '
        'age to determine whether you need permission from a parent or '
        'guardian. We save the age you enter, the date and version of your policy acceptance, '
        'and record your guardian consent confirmation if you are under 18.',
  ),
  (
    'Who can see your records',
    'You can view the records saved to your account. Your current assigned '
        'dietitian can view only the categories you choose to share. Other '
        'clients, unassigned dietitians, staff and admins do not have access '
        'to those private records through the app.',
  ),
  (
    'Photos and device activity',
    'Meal photos, progress photos and device activity are optional. FitNEP '
        'does not collect them unless you enable the matching choice in '
        'Privacy preferences.',
  ),
  (
    'Changing your choices',
    'You can change your choices in Privacy preferences. Turning off a '
        'photo or activity setting stops new collection and removes your '
        'dietitian’s access. Your saved records remain available to you. '
        'Turning off nutrition sharing keeps your manually entered logs private.',
  ),
];
