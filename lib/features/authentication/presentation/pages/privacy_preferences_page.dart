import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../core/constants/privacy_policy.dart';
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

  Future<void> _save(PrivacySharingCategory category, bool enabled) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await ref
          .read(privacyPreferencesControllerProvider.notifier)
          .setSharing(category, enabled);
    } catch (_) {
      if (mounted) {
        ref.invalidate(privacyPreferencesControllerProvider);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Could not confirm the change. Refreshing your choices.',
              ),
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
      appBar: AppBar(
        title: const Text('Privacy preferences'),
        actions: [
          TextButton(
            onPressed: () => context.pushNamed(AppRoutes.privacyPolicy),
            child: const Text('Privacy Policy'),
          ),
        ],
      ),
      body: SafeArea(
        child: preferences.when(
          skipLoadingOnRefresh: false,
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
                PrivacyPolicyText.sharingIntroduction,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              const Text(PrivacyPolicyText.recordAccess),
              if (_isSaving) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 24),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final (category, icon, title) in _sharingOptions)
                      _PrivacyOption(
                        icon: icon,
                        title: title,
                        description: value.isShared(category)
                            ? PrivacyPolicyText.sharedVisibility
                            : PrivacyPolicyText.privateVisibility,
                        value: value.isShared(category),
                        onChanged: _isSaving
                            ? null
                            : (enabled) => _save(category, enabled),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                PrivacyPolicyText.withdrawal,
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

const _sharingOptions = [
  (
    PrivacySharingCategory.nutritionRecords,
    Icons.restaurant_outlined,
    'Share nutrition records',
  ),
  (
    PrivacySharingCategory.mealPhotos,
    Icons.photo_camera_outlined,
    'Share meal photos',
  ),
  (
    PrivacySharingCategory.progressPhotos,
    Icons.photo_library_outlined,
    'Share progress photos',
  ),
  (
    PrivacySharingCategory.activityData,
    Icons.directions_walk_outlined,
    'Share device activity',
  ),
];

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
