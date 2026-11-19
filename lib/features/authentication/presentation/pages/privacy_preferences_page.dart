import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/privacy_preferences.dart';
import '../controllers/privacy_preferences_controller.dart';

class PrivacyPreferencesPage extends ConsumerStatefulWidget {
  const PrivacyPreferencesPage({super.key});

  @override
  ConsumerState<PrivacyPreferencesPage> createState() =>
      _PrivacyPreferencesPageState();
}

class _PrivacyPreferencesPageState
    extends ConsumerState<PrivacyPreferencesPage> {
  bool _isSaving = false;

  Future<void> _save(PrivacyPreferences preferences) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await ref
          .read(privacyPreferencesControllerProvider.notifier)
          .savePreferences(preferences);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Could not save your choices. Please try again.'),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferences = ref.watch(privacyPreferencesControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy preferences')),
      body: SafeArea(
        child: preferences.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _LoadError(
            onRetry: () => ref.invalidate(privacyPreferencesControllerProvider),
          ),
          data: (value) => ListView(
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
                'Choose whether your assigned dietitian can view your nutrition '
                'records. Sharing is off until you turn it on.',
                style: theme.textTheme.bodyLarge,
              ),
              if (_isSaving) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 24),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _PrivacyOption(
                      icon: Icons.restaurant_outlined,
                      title: 'Share nutrition records',
                      description:
                          'Allow your assigned dietitian to view your '
                          'nutrition logs.',
                      value: value.shareNutritionRecords,
                      onChanged: _isSaving
                          ? null
                          : (enabled) => _save(
                              value.copyWith(shareNutritionRecords: enabled),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Your own nutrition records remain available to you regardless '
                'of this setting. This preference is stored on this device and '
                'can be changed at any time.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load your privacy choices.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
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
  final ValueChanged<bool>? onChanged;

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
