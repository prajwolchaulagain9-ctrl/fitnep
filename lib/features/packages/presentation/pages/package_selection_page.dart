import '../../../../shared/widgets/wellness_illustration.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../authorization/presentation/role_home_page.dart';
import '../../../authentication/presentation/sign_out_to_welcome.dart';
import '../../../admin/domain/entities/package_entity.dart';
import '../../../admin/presentation/controllers/package_management_controller.dart';
import '../../../admin/presentation/widgets/empty_state_widget.dart';
import '../../../purchases/presentation/controllers/membership_controller.dart';
import '../widgets/package_card_header.dart';

class _ActivePackageState {
  const _ActivePackageState({
    required this.packages,
    required this.isLoading,
    this.errorMessage,
  });
  final List<PackageEntity> packages;
  final bool isLoading;
  final String? errorMessage;
}

class PackageSelectionPage extends ConsumerWidget {
  const PackageSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(activePackagesProvider);
    final state = _ActivePackageState(
      packages: catalog.value ?? const [],
      isLoading: catalog.isLoading,
      errorMessage: catalog.hasError ? catalog.error.toString() : null,
    );
    final membership = ref.watch(membershipControllerProvider);
    Future<void> refresh() async {
      await Future.wait([
        ref.refresh(activePackagesProvider.future),
        ref.read(membershipControllerProvider.notifier).refresh(),
      ]);
    }

    return Scaffold(
      drawer: const RoleNavigationDrawer(),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Choose a package',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: state.isLoading || membership.isPurchasing
                ? null
                : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => signOutToWelcome(context, ref),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: _PackageSelectionBody(
        state: state,
        membership: membership,
        onRefresh: refresh,
        onPurchase: (package) => _purchasePackage(context, ref, package),
      ),
    );
  }
}

class _PackageSelectionBody extends StatelessWidget {
  final _ActivePackageState state;
  final MembershipState membership;
  final Future<void> Function() onRefresh;
  final Future<void> Function(PackageEntity package) onPurchase;

  const _PackageSelectionBody({
    required this.state,
    required this.membership,
    required this.onRefresh,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isLoading && state.packages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading packages...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    if (state.errorMessage != null && state.packages.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: 'Failed to load packages',
        subtitle: state.errorMessage!,
        actionLabel: 'Retry',
        onAction: onRefresh,
      );
    }
    if (state.packages.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.inventory_2_outlined,
        title: 'No packages available',
        subtitle:
            'No fitness packages are currently available. Check back later.',
        actionLabel: 'Continue to dashboard',
        onAction: () => context.go(AppRoutes.clientHome),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.packages.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (context, index) => index == 0
            ? _intro(context)
            : _CustomerPackageCard(
                package: state.packages[index - 1],
                membership: membership,
                onPurchase: onPurchase,
              ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final theme = Theme.of(context);
    final purchase = membership.purchase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Support that fits your goals.',
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(width: 12),
            const WellnessIllustration(size: 70),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Explore your options and take the next step at your pace.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (purchase != null && purchase.isCurrent) ...[
          const SizedBox(height: 20),
          Container(
            key: const Key('current_package_summary'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${purchase.packageName} is your current package',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  purchase.isPending
                      ? 'Your selection is saved and awaiting payment verification. You can continue to your home.'
                      : 'Your membership is ${purchase.statusLabel.toLowerCase()}. This package is already selected.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                Tooltip(
                  message: 'Continue to home',
                  child: FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.clientHome),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                    iconAlignment: IconAlignment.end,
                    label: const Text('Continue to home'),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (membership.hasMembershipCheckFailed) ...[
          const SizedBox(height: 16),
          Text(
            'We couldn’t check your current membership. Please retry before choosing a package.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry membership check'),
          ),
        ],
      ],
    );
  }
}

class _CustomerPackageCard extends StatelessWidget {
  final PackageEntity package;
  final MembershipState membership;
  final Future<void> Function(PackageEntity package) onPurchase;

  const _CustomerPackageCard({
    required this.package,
    required this.membership,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final purchase = membership.purchase;
    final isSelected =
        purchase?.isCurrent == true && purchase?.packageId == package.id;
    final pending = purchase?.isPending == true;
    final saving =
        membership.isPurchasing && membership.purchasingPackageId == package.id;
    final enabled =
        !membership.isLoading &&
        !membership.isPurchasing &&
        !isSelected &&
        !pending &&
        !membership.hasMembershipCheckFailed;
    final currency = NumberFormat.currency(
      locale: 'en_NP',
      symbol: 'NPR ',
      decimalDigits: package.price % 1 == 0 ? 0 : 2,
    );
    final label = isSelected
        ? 'Selected'
        : membership.isLoading
        ? 'Checking membership…'
        : saving
        ? 'Saving selection…'
        : pending
        ? 'Available after verification'
        : 'Choose ${package.name}';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isSelected ? colors.primary : colors.outlineVariant,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PackageCardHeader(
              packageName: package.name,
              titleStyle: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              trailing: isSelected
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.statusActive,
                      size: 22,
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                Text(
                  currency.format(package.price),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                ),
                Text(
                  'for ${package.durationMonths} ${package.durationMonths == 1 ? 'month' : 'months'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Divider(color: colors.outlineVariant),
            const SizedBox(height: 18),
            Text(
              package.featureDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            Semantics(
              selected: isSelected,
              child: FilledButton.icon(
                key: Key('select_package_${package.id}'),
                onPressed: enabled ? () => onPurchase(package) : null,
                style: isSelected
                    ? FilledButton.styleFrom(
                        disabledBackgroundColor: colors.primaryContainer,
                        disabledForegroundColor: colors.onSurface,
                      )
                    : null,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isSelected
                            ? Icons.check_rounded
                            : pending
                            ? Icons.lock_outline_rounded
                            : Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                iconAlignment: isSelected || pending
                    ? IconAlignment.start
                    : IconAlignment.end,
                label: Text(label, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _purchasePackage(
  BuildContext context,
  WidgetRef ref,
  PackageEntity package,
) async {
  final membership = ref.read(membershipControllerProvider);
  final current = membership.purchase;
  if (membership.isLoading ||
      membership.isPurchasing ||
      membership.hasMembershipCheckFailed ||
      current?.isPending == true ||
      (current?.isCurrent == true && current?.packageId == package.id)) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Choose ${package.name}?'),
      content: const Text(
        'Your price, duration, and included features will be saved. Your membership remains Pending until payment is verified.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Confirm selection'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  try {
    await ref
        .read(membershipControllerProvider.notifier)
        .purchasePackage(package.id);
    if (context.mounted) context.go(AppRoutes.clientHome);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error.toString())));
  }
}
