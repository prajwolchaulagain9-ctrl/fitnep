import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/app_routes.dart';
import '../../../../app/routes/route_access_gate.dart';
import '../../../authorization/data/authorization_repository.dart';
import '../../../authorization/domain/account.dart';
import '../controllers/audit_log_controller.dart';
import '../widgets/audit_log_tile.dart';

const _nepalOffset = Duration(hours: 5, minutes: 45);
const _filterLabels = {
  'actor_id': 'Actor ID',
  'action': 'Action',
  'client_id': 'Client ID',
  'dietitian_id': 'Dietitian ID',
  'status': 'Status',
  'plan_id': 'Plan ID',
};

class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  final _events = <Map<String, dynamic>>[];
  Map<String, String> _filters = const {};
  String? _nextCursor;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _events.clear();
        _nextCursor = null;
      }
    });
    try {
      final data = await ref
          .read(authorizationRepositoryProvider)
          .request(
            'admin/audit-events',
            query: {..._filters, if (more) 'after': _nextCursor},
          );
      final events = (data['events'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final nextCursor = data['next_cursor'] as String?;
      if (!mounted) return;
      setState(() {
        _events.addAll(events);
        _nextCursor = nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _events.clear();
        _nextCursor = null;
        _error = error is AuthorizationFailure
            ? error.message
            : 'The audit events could not be loaded. Try again.';
        _loading = false;
      });
    }
  }

  void _apply(Map<String, String> filters) {
    _filters = filters;
    _load();
  }

  Future<void> _showFilters() async {
    final draft = Map<String, String>.of(_filters);
    final dateFormat = DateFormat('yyyy-MM-dd');
    final today = DateTime.now().toUtc().add(_nepalOffset);
    final selection = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) {
          final start = draft['from'];
          final end = draft['through'];
          return AlertDialog(
            title: const Text('Filter audit events'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final field in _filterLabels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      initialValue: draft[field.key],
                      decoration: InputDecoration(
                        labelText: field.value,
                        hintText: switch (field.key) {
                          'action' => 'client.assigned',
                          'status' => 'reviewed',
                          _ => null,
                        },
                      ),
                      onChanged: (value) {
                        final trimmed = value.trim();
                        if (trimmed.isEmpty) {
                          draft.remove(field.key);
                        } else {
                          draft[field.key] = trimmed;
                        }
                      },
                    ),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    start == null || end == null
                        ? 'Date range (Nepal time)'
                        : '$start to $end',
                  ),
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(today.year + 1, 12, 31),
                      initialDateRange: start == null || end == null
                          ? null
                          : DateTimeRange(
                              start: DateTime.parse(start),
                              end: DateTime.parse(end),
                            ),
                      currentDate: DateTime(today.year, today.month, today.day),
                      helpText: 'Audit date range (Nepal time)',
                    );
                    if (range == null || !context.mounted) return;
                    updateDialog(() {
                      draft['from'] = dateFormat.format(range.start);
                      draft['through'] = dateFormat.format(range.end);
                    });
                  },
                ),
                if (start != null)
                  TextButton(
                    onPressed: () => updateDialog(() {
                      draft.remove('from');
                      draft.remove('through');
                    }),
                    child: const Text('Clear dates'),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(draft),
                child: const Text('Apply filters'),
              ),
            ],
          );
        },
      ),
    );
    if (mounted && selection != null) _apply(selection);
  }

  @override
  Widget build(BuildContext context) {
    final admin =
        ref.watch(routeSessionProvider).value?.role == FitNepRole.admin;
    final plan = _filters['plan_id'];
    return Scaffold(
      appBar: AppBar(
        title: Text(plan == null ? 'Audit log' : 'Plan timeline'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filter audit events',
            onPressed: _loading ? null : _showFilters,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(),
          ),
          if (admin)
            PopupMenuButton<String>(
              tooltip: 'Audit history',
              onSelected: (path) => context.push(path),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: AppRoutes.legacyAuditLog,
                  child: Text('Legacy authorization log'),
                ),
                PopupMenuItem(
                  value: AppRoutes.adminStaffHistory,
                  child: Text('Staff account history'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_filters.isNotEmpty)
              ListTile(
                title: Text(
                  _filters.entries
                      .map((filter) {
                        final label = _filterLabels[filter.key] ?? filter.key;
                        return '$label ${filter.value}';
                      })
                      .join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  onPressed: _loading ? null : () => _apply(const {}),
                  child: const Text('Clear'),
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(12),
                  itemCount: _events.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _events.length) return _footer();
                    final event = _events[index];
                    return _AuditEventTile(
                      event: event,
                      openPlan: !_loading && plan == null
                          ? (id) => _apply({'plan_id': id})
                          : null,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    if (_error case final error?) {
      return Column(
        children: [
          Text(error, textAlign: TextAlign.center),
          TextButton(onPressed: () => _load(), child: const Text('Try again')),
        ],
      );
    }
    if (_nextCursor != null) {
      return Column(
        children: [
          if (_events.isEmpty) const Text('No matches on this page.'),
          OutlinedButton(
            onPressed: _loading ? null : () => _load(more: true),
            child: const Text('Load more'),
          ),
        ],
      );
    }
    if (_events.isEmpty && !_loading) {
      return const Center(child: Text('No audit events found.'));
    }
    return const SizedBox.shrink();
  }
}

class _AuditEventTile extends StatelessWidget {
  const _AuditEventTile({required this.event, required this.openPlan});

  final Map<String, dynamic> event;
  final ValueChanged<String>? openPlan;

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime.parse(event['occurred_at'] as String)
        .toUtc()
        .add(_nepalOffset);
    final time = DateFormat('dd MMM yyyy, HH:mm:ss').format(timestamp);
    final actor = event['actor_name'] ?? event['actor_id'];
    final targetId = event['target_id'] as String;
    final outcome = event['outcome'];
    final details = {
      'Actor ID': event['actor_id'],
      'Role': event['actor_role'],
      'Target ID': targetId,
      'Client ID': event['client_id'],
      'Dietitian ID': event['dietitian_id'],
      'Previous dietitian ID': event['previous_dietitian_id'],
      'Status': event['status'],
      'Version': event['version'],
      'Request ID': event['correlation_id'],
      'Record IDs': (event['record_ids'] as List?)?.join(', '),
    };
    return Card(
      child: ExpansionTile(
        key: ValueKey(event['id']),
        title: Text(event['action'] as String),
        subtitle: Text(
          '$actor • $outcome\n${event['target_type']} • $targetId\n$time NPT',
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final field in details.entries)
            if (field.value != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText('${field.key}  ${field.value}'),
              ),
          if (event['target_type'] == 'plan' && openPlan != null)
            TextButton(
              onPressed: () => openPlan!(targetId),
              child: const Text('View plan timeline'),
            ),
        ],
      ),
    );
  }
}

class LegacyAuditLogPage extends ConsumerWidget {
  const LegacyAuditLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(auditLogControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Legacy authorization log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(auditLogControllerProvider),
          ),
        ],
      ),
      body: state.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
        data: (logs) => logs.isEmpty
            ? const Center(child: Text('No legacy audit logs found.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: logs.length,
                itemBuilder: (context, index) => AuditLogTile(
                  log: logs[index],
                  isLast: index == logs.length - 1,
                ),
              ),
      ),
    );
  }
}
