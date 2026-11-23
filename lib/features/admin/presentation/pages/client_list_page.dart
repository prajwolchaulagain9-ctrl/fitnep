import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controllers/client_list_controller.dart';
import '../widgets/client_card.dart';
import '../widgets/empty_state_widget.dart';
import '../../domain/entities/client_entity.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/routes/app_routes.dart';
import '../../../authentication/presentation/sign_out_to_welcome.dart';

class ClientListPage extends ConsumerStatefulWidget {
  const ClientListPage({super.key});

  @override
  ConsumerState<ClientListPage> createState() => _ClientListPageState();
}

class _ClientListPageState extends ConsumerState<ClientListPage> {
  final _searchController = TextEditingController();
  bool _searchExpanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientListControllerProvider);
    final controller = ref.read(clientListControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(context, state, controller, innerBoxIsScrolled),
        ],
        body: _buildBody(context, state, controller),
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    ClientListState state,
    ClientListController controller,
    bool innerBoxIsScrolled,
  ) {
    final isCompact = MediaQuery.sizeOf(context).width < 480;

    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: AppColors.surface,
      expandedHeight: 0,
      pinned: false,
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _searchExpanded
            ? _SearchField(
                key: const ValueKey('search'),
                controller: _searchController,
                onChanged: controller.updateSearch,
                onClose: () {
                  setState(() => _searchExpanded = false);
                  _searchController.clear();
                  controller.updateSearch('');
                },
              )
            : _AppBarTitle(
                key: const ValueKey('title'),
                clientCount: state.filteredClients.length,
                totalCount: state.allClients.length,
              ),
      ),
      actions: _searchExpanded
          ? const [SizedBox(width: 8)]
          : [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search clients',
                onPressed: () => setState(() => _searchExpanded = true),
              ),
              _FilterButton(
                state: state,
                onFilter: () => _showFilterMenu(context, state, controller),
              ),
              if (isCompact)
                _ClientAppBarOverflow(
                  onPackages: () => context.push(AppRoutes.adminPackages),
                  onStaffAccounts: () =>
                      context.push(AppRoutes.adminStaffAccounts),
                  onNotifications: () => context.push(AppRoutes.notifications),
                  onAuditLog: () => context.push(AppRoutes.auditLog),
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.inventory_2_outlined),
                  tooltip: 'Package Management',
                  onPressed: () => context.push(AppRoutes.adminPackages),
                ),
                IconButton(
                  icon: const Icon(Icons.manage_accounts_outlined),
                  tooltip: 'Manage staff accounts',
                  onPressed: () => context.push(AppRoutes.adminStaffAccounts),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  tooltip: 'Notifications',
                  onPressed: () => context.push(AppRoutes.notifications),
                ),
                IconButton(
                  icon: const Icon(Icons.history_rounded),
                  tooltip: 'Audit Log',
                  onPressed: () => context.push(AppRoutes.auditLog),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'Sign out',
                  onPressed: () => signOutToWelcome(context, ref),
                ),
              ],
              const SizedBox(width: 4),
            ],
      bottom: state.filters.activeCount > 0 || state.searchQuery.isNotEmpty
          ? PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: _ActiveFiltersBar(
                state: state,
                onClear: () {
                  controller.clearFilters();
                  _searchController.clear();
                  setState(() => _searchExpanded = false);
                },
              ),
            )
          : null,
    );
  }

  Widget _buildBody(
    BuildContext context,
    ClientListState state,
    ClientListController controller,
  ) {
    if (state.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading clients...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (state.errorMessage != null) {
      return EmptyStateWidget(
        icon: Icons.wifi_off_rounded,
        title: 'Failed to load clients',
        subtitle: state.errorMessage!,
        actionLabel: 'Retry',
        onAction: controller.refresh,
      );
    }

    if (state.filteredClients.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.person_search_rounded,
        title: 'No clients found',
        subtitle: state.searchQuery.isNotEmpty || !state.filters.isEmpty
            ? 'Try different search terms or clear the active filters.'
            : 'There are no clients registered yet.',
        actionLabel: state.searchQuery.isNotEmpty || !state.filters.isEmpty
            ? 'Clear Filters'
            : null,
        onAction: state.searchQuery.isNotEmpty || !state.filters.isEmpty
            ? () {
                controller.clearFilters();
                _searchController.clear();
                setState(() => _searchExpanded = false);
              }
            : null,
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceElevated,
      onRefresh: controller.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: state.filteredClients.length,
        itemBuilder: (context, index) {
          final client = state.filteredClients[index];
          return ClientCard(
            client: client,
            onTap: () => context.push('/admin/clients/${client.id}'),
          );
        },
      ),
    );
  }

  Future<void> _showFilterMenu(
    BuildContext context,
    ClientListState state,
    ClientListController controller,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FilterMenuSheet(
        state: state,
        onApply: controller.updateFilters,
        onClear: controller.clearFilters,
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────────────────────

class _AppBarTitle extends StatelessWidget {
  final int clientCount;
  final int totalCount;

  const _AppBarTitle({
    super.key,
    required this.clientCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'Client Management',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(
          '$clientCount of $totalCount clients',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by name...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: onClose,
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final ClientListState state;
  final VoidCallback onFilter;

  const _FilterButton({required this.state, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final count = state.filters.activeCount;
    return Stack(
      alignment: Alignment.topRight,
      children: [
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          tooltip: 'Filter',
          onPressed: onFilter,
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

enum _ClientAppBarAction {
  packages,
  staffAccounts,
  notifications,
  auditLog,
  signOut,
}

class _ClientAppBarOverflow extends ConsumerWidget {
  final VoidCallback onPackages;
  final VoidCallback onStaffAccounts;
  final VoidCallback onNotifications;
  final VoidCallback onAuditLog;

  const _ClientAppBarOverflow({
    required this.onPackages,
    required this.onStaffAccounts,
    required this.onNotifications,
    required this.onAuditLog,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ClientAppBarAction>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        if (action == _ClientAppBarAction.packages) {
          onPackages();
        } else if (action == _ClientAppBarAction.staffAccounts) {
          onStaffAccounts();
        } else if (action == _ClientAppBarAction.notifications) {
          onNotifications();
        } else if (action == _ClientAppBarAction.auditLog) {
          onAuditLog();
        } else if (action == _ClientAppBarAction.signOut) {
          signOutToWelcome(context, ref);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ClientAppBarAction.packages,
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined),
              SizedBox(width: 12),
              Flexible(child: Text('Package Management')),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ClientAppBarAction.staffAccounts,
          child: Row(
            children: [
              Icon(Icons.manage_accounts_outlined),
              SizedBox(width: 12),
              Flexible(child: Text('Manage staff accounts')),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ClientAppBarAction.notifications,
          child: Row(
            children: [
              Icon(Icons.notifications_none_rounded),
              SizedBox(width: 12),
              Text('Notifications'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _ClientAppBarAction.auditLog,
          child: Row(
            children: [
              Icon(Icons.history_rounded),
              SizedBox(width: 12),
              Text('Audit Log'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _ClientAppBarAction.signOut,
          child: Row(
            children: [
              Icon(Icons.logout_rounded),
              SizedBox(width: 12),
              Text('Sign out'),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveFiltersBar extends StatelessWidget {
  final ClientListState state;
  final VoidCallback onClear;

  const _ActiveFiltersBar({required this.state, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (state.searchQuery.isNotEmpty)
                    _FilterTag(
                      label: '"${state.searchQuery}"',
                      icon: Icons.search_rounded,
                    ),
                  ...state.filters.packages.map(
                    (p) =>
                        _FilterTag(label: p, icon: Icons.inventory_2_outlined),
                  ),
                  ...state.filters.statuses.map(
                    (s) => _FilterTag(
                      label: s == ClientStatus.active ? 'Active' : 'Inactive',
                      icon: Icons.circle,
                      color: s == ClientStatus.active
                          ? AppColors.statusActive
                          : AppColors.statusInactive,
                    ),
                  ),
                  ...state.filters.dietitians.map(
                    (d) => _FilterTag(
                      label: d,
                      icon: Icons.person_outline_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Clear all', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.statusInactive,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _FilterTag({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color ?? AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Menu Sheet ───────────────────────────────────────────────────────

class _FilterMenuSheet extends ConsumerStatefulWidget {
  final ClientListState state;
  final ValueChanged<ClientFilters> onApply;
  final VoidCallback onClear;

  const _FilterMenuSheet({
    required this.state,
    required this.onApply,
    required this.onClear,
  });

  @override
  ConsumerState<_FilterMenuSheet> createState() => _FilterMenuSheetState();
}

class _FilterMenuSheetState extends ConsumerState<_FilterMenuSheet> {
  late Set<String> _packages;
  late Set<ClientStatus> _statuses;
  late Set<String> _dietitians;

  @override
  void initState() {
    super.initState();
    _packages = Set.from(widget.state.filters.packages);
    _statuses = Set.from(widget.state.filters.statuses);
    _dietitians = Set.from(widget.state.filters.dietitians);
  }

  @override
  Widget build(BuildContext context) {
    final availablePackages = widget.state.availablePackages.toList()..sort();
    final availableDietitians = widget.state.availableDietitians.toList()
      ..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Filter Clients',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _packages.clear();
                      _statuses.clear();
                      _dietitians.clear();
                    });
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable content
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _SectionHeader('Package'),
                ...availablePackages.map(
                  (pkg) => CheckboxListTile(
                    title: Text(
                      pkg,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    value: _packages.contains(pkg),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _packages.add(pkg);
                      } else {
                        _packages.remove(pkg);
                      }
                    }),
                    activeColor: AppColors.primary,
                    checkColor: Colors.white,
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                _SectionHeader('Account Status'),
                CheckboxListTile(
                  title: Text(
                    'Active',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                  value: _statuses.contains(ClientStatus.active),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _statuses.add(ClientStatus.active);
                    } else {
                      _statuses.remove(ClientStatus.active);
                    }
                  }),
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                CheckboxListTile(
                  title: Text(
                    'Inactive',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textPrimary),
                  ),
                  value: _statuses.contains(ClientStatus.inactive),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _statuses.add(ClientStatus.inactive);
                    } else {
                      _statuses.remove(ClientStatus.inactive);
                    }
                  }),
                  activeColor: AppColors.primary,
                  checkColor: Colors.white,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(indent: 16, endIndent: 16),
                _SectionHeader('Assigned Dietitian'),
                ...availableDietitians.map(
                  (diet) => CheckboxListTile(
                    title: Text(
                      diet,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    value: _dietitians.contains(diet),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _dietitians.add(diet);
                      } else {
                        _dietitians.remove(diet);
                      }
                    }),
                    activeColor: AppColors.primary,
                    checkColor: Colors.white,
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
          // Apply button
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ).copyWith(bottom: MediaQuery.of(context).viewInsets.bottom + 16),
            decoration: const BoxDecoration(
              color: AppColors.surfaceElevated,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(
                    ClientFilters(
                      packages: _packages,
                      statuses: _statuses,
                      dietitians: _dietitians,
                    ),
                  );
                  Navigator.pop(context);
                },
                child: const Text('Apply Filters'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textDisabled,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
