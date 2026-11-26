import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/routes/route_access_gate.dart';
import '../data/authorization_repository.dart';
import '../domain/account.dart';
import '../domain/assigned_client.dart';

class AssignedClientsPage extends ConsumerStatefulWidget {
  const AssignedClientsPage({super.key});

  @override
  ConsumerState<AssignedClientsPage> createState() =>
      _AssignedClientsPageState();
}

class _AssignedClientsPageState extends ConsumerState<AssignedClientsPage> {
  final _clients = <AssignedClient>[];
  String _search = '';
  AssignedClientPlanStatus? _planStatus;
  String? _nextCursor;
  String? _error;
  Timer? _searchDebounce;
  int _request = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch(_request));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reload({bool debounce = false}) async {
    _searchDebounce?.cancel();
    final request = ++_request;
    setState(() {
      _clients.clear();
      _nextCursor = null;
      _error = null;
      _loading = true;
    });
    if (debounce) {
      _searchDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_fetch(request)),
      );
    } else {
      await _fetch(request);
    }
  }

  Future<void> _fetch(int request, {String? after}) async {
    try {
      final page = await ref
          .read(authorizationRepositoryProvider)
          .assignedClients(
            search: _search.isEmpty ? null : _search,
            planStatus: _planStatus,
            after: after,
          );
      if (!mounted || request != _request) return;
      setState(() {
        _clients.addAll(page.clients);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _clients.clear();
        _nextCursor = null;
        _error = error is AuthorizationFailure
            ? error.message
            : 'Could not load assigned clients. Please try again.';
        _loading = false;
      });
    }
  }

  void _loadMore() {
    final cursor = _nextCursor;
    if (_loading || cursor == null) return;
    setState(() => _loading = true);
    unawaited(_fetch(_request, after: cursor));
  }

  Future<void> _open(AssignedClient client) async {
    await context.pushNamed(
      AppRoutes.dietitianAssignedClientName,
      pathParameters: {'id': client.id},
    );
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final isDietitian =
        ref.watch(routeSessionProvider).value?.role == FitNepRole.dietitian;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assigned clients'),
        actions: [
          IconButton(
            onPressed: () => _reload(),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (isDietitian)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    TextField(
                      maxLength: 120,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search by client name',
                        counterText: '',
                      ),
                      onChanged: (value) {
                        final search = value.trim();
                        if (search == _search) return;
                        _search = search;
                        unawaited(_reload(debounce: true));
                      },
                      onSubmitted: (_) => _reload(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _planStatus?.apiValue ?? '',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Plan status',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('All plans'),
                        ),
                        for (final status in AssignedClientPlanStatus.values)
                          if (status != AssignedClientPlanStatus.unavailable)
                            DropdownMenuItem(
                              value: status.apiValue,
                              child: Text(status.label),
                            ),
                      ],
                      onChanged: (value) {
                        _planStatus = value == null || value.isEmpty
                            ? null
                            : AssignedClientPlanStatus.fromApi(value);
                        unawaited(_reload());
                      },
                    ),
                  ],
                ),
              ),
            Expanded(child: _buildResults(isDietitian)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(bool isDietitian) {
    if (_clients.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              TextButton(
                onPressed: () => _reload(),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          for (final client in _clients)
            _AssignedClientCard(
              key: ValueKey(client.id),
              client: client,
              onOpen: isDietitian ? () => _open(client) : null,
            ),
          if (_clients.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _search.isEmpty && _planStatus == null
                    ? 'No active clients are assigned to you.'
                    : 'No assigned clients match your search and filters.',
                textAlign: TextAlign.center,
              ),
            ),
          if (_nextCursor != null)
            Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: _loadMore,
                      child: const Text('Load more'),
                    ),
            ),
        ],
      ),
    );
  }
}

class _AssignedClientCard extends StatelessWidget {
  const _AssignedClientCard({
    required this.client,
    required this.onOpen,
    super.key,
  });

  final AssignedClient client;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final lastActivity = client.lastActivityAt;
    final activityLabel = lastActivity == null
        ? 'No activity recorded'
        : MaterialLocalizations.of(context)
              .formatMediumDate(lastActivity.toLocal());
    final intake = client.intakeStatus;
    return Card(
      child: ListTile(
        title: Text(client.fullName.isEmpty ? client.email : client.fullName),
        subtitle: onOpen == null
            ? Text(client.email)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Package: ${client.packageStatus}'),
                  Text('Plan: ${client.planStatus.label}'),
                  if (intake != null) Text('Intake: $intake'),
                  Text('Last activity: $activityLabel'),
                ],
              ),
        trailing: onOpen == null ? null : const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}
