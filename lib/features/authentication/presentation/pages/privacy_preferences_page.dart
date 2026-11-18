import 'package:flutter/material.dart';

import '../../domain/entities/privacy_preferences.dart';

class PrivacyPreferencesPage extends StatefulWidget {
  const PrivacyPreferencesPage({super.key});

  @override
  State<PrivacyPreferencesPage> createState() => _PrivacyPreferencesPageState();
}

class _PrivacyPreferencesPageState extends State<PrivacyPreferencesPage> {
  var _preferences = PrivacyPreferences.defaults;

  void _updatePreferences(PrivacyPreferences preferences) {
    setState(() => _preferences = preferences);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy preferences')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'You’re in control',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which information you’re comfortable sharing with your '
              'FitNEP care team. Sharing is off until you turn it on.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _PrivacyOption(
                    icon: Icons.restaurant_outlined,
                    title: 'Meal photos',
                    description:
                        'Let your care team review meal photos you submit.',
                    value: _preferences.shareMealPhotos,
                    onChanged: (value) => _updatePreferences(
                      _preferences.copyWith(shareMealPhotos: value),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _PrivacyOption(
                    icon: Icons.photo_camera_back_outlined,
                    title: 'Progress photos',
                    description: 'Share progress photos with your care team.',
                    value: _preferences.shareProgressPhotos,
                    onChanged: (value) => _updatePreferences(
                      _preferences.copyWith(shareProgressPhotos: value),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _PrivacyOption(
                    icon: Icons.directions_run_outlined,
                    title: 'Activity data',
                    description:
                        'Share activity information to support your plan.',
                    value: _preferences.shareActivityData,
                    onChanged: (value) => _updatePreferences(
                      _preferences.copyWith(shareActivityData: value),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can change these choices at any time.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(description),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}
