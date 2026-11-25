import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/routes/route_access_gate.dart';
import '../../../shared/widgets/fitnep_wordmark.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../authentication/presentation/controllers/authentication_controller.dart';

typedef RoleMenuItem = ({
  String label,
  String permission,
  String path,
  IconData icon,
});
const roleMenuItems = <RoleMenuItem>[
  (
    label: 'Staff accounts',
    permission: 'manage_staff_accounts',
    path: AppRoutes.adminStaffAccounts,
    icon: Icons.badge_outlined,
  ),
  (
    label: 'Staff account history',
    permission: 'manage_staff_accounts',
    path: AppRoutes.adminStaffHistory,
    icon: Icons.history,
  ),
  (
    label: 'My profile',
    permission: 'view_own_profile',
    path: AppRoutes.ownProfile,
    icon: Icons.person_outline,
  ),
  (
    label: 'Notifications',
    permission: 'view_own_notifications',
    path: AppRoutes.notifications,
    icon: Icons.notifications_outlined,
  ),
  (
    label: 'My records and diet plans',
    permission: 'view_client_dashboard',
    path: AppRoutes.clientRecords,
    icon: Icons.restaurant_menu,
  ),
  (
    label: 'Packages',
    permission: 'manage_own_membership',
    path: AppRoutes.clientPackages,
    icon: Icons.inventory_2_outlined,
  ),
  (
    label: 'Membership',
    permission: 'manage_own_membership',
    path: AppRoutes.clientMembership,
    icon: Icons.card_membership,
  ),
  (
    label: 'Privacy preferences',
    permission: 'manage_own_privacy',
    path: AppRoutes.clientPrivacyPreferences,
    icon: Icons.privacy_tip_outlined,
  ),
  (
    label: 'Assigned clients',
    permission: 'view_assigned_clients',
    path: AppRoutes.assignedClients,
    icon: Icons.people_outline,
  ),
  (
    label: 'Users and roles',
    permission: 'manage_user_roles',
    path: AppRoutes.adminUsers,
    icon: Icons.manage_accounts_outlined,
  ),
  (
    label: 'Client accounts',
    permission: 'manage_client_accounts',
    path: AppRoutes.adminClients,
    icon: Icons.people_alt_outlined,
  ),
  (
    label: 'Package management',
    permission: 'manage_business_settings',
    path: AppRoutes.adminPackages,
    icon: Icons.inventory_outlined,
  ),
  (
    label: 'Payment approvals',
    permission: 'manage_business_settings',
    path: AppRoutes.adminPackageApprovals,
    icon: Icons.payments_outlined,
  ),
  (
    label: 'Package history',
    permission: 'manage_business_settings',
    path: AppRoutes.adminPackageHistory,
    icon: Icons.history,
  ),
  (
    label: 'Audit logs',
    permission: 'view_audit_logs',
    path: AppRoutes.auditLog,
    icon: Icons.policy_outlined,
  ),
];
List<RoleMenuItem> menusForRole(FitNepRole? role) => roleMenuItems
    .where((item) => AuthorizationService(role).hasPermission(item.permission))
    .toList();

class RoleHomePage extends ConsumerWidget {
  const RoleHomePage({required this.role, super.key});
  final FitNepRole role;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text('${role.label} dashboard')),
    drawer: const RoleNavigationDrawer(),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(child: FitNepWordmark(width: 90)),
        const SizedBox(height: 20),
        Text(
          'Welcome to FitNEP',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Your ${role.label.toLowerCase()} workspace',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        for (final item in menusForRole(role))
          Card(
            child: ListTile(
              leading: Icon(item.icon),
              title: Text(item.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(item.path),
            ),
          ),
      ],
    ),
  );
}

class RoleNavigationDrawer extends ConsumerWidget {
  const RoleNavigationDrawer({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(routeSessionProvider).value?.role;
    final action = ref.watch(authenticationControllerProvider);
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FitNepWordmark(width: 76),
                  const SizedBox(height: 12),
                  Text(
                    role?.label ?? 'Checking permissions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            if (role != null)
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Dashboard'),
                onTap: () => context.go(dashboardForRole(role)),
              ),
            for (final item in menusForRole(role))
              ListTile(
                leading: Icon(item.icon),
                title: Text(item.label),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(item.path);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Appearance'),
              trailing: DropdownButton<ThemeMode>(
                value: ref.watch(themeModeProvider),
                onChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).select(mode);
                  }
                },
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('System'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('Light'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
              ),
            ),
            if (action.errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(action.errorMessage!),
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: action.isLoading
                  ? null
                  : () async {
                      final success = await ref
                          .read(authenticationControllerProvider.notifier)
                          .signOut();
                      if (success && context.mounted) {
                        context.go(AppRoutes.loginPath);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
