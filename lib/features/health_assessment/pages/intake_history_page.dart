import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/client_intake_remote_datasource.dart';
import '../data/intake_history_repository.dart';

class IntakeHistoryPage extends ConsumerStatefulWidget {
  const IntakeHistoryPage({
    super.key,
    required this.clientId,
    required this.openVersion,
  });

  final String clientId;
  final Future<void> Function(BuildContext, int) openVersion;

  @override
  ConsumerState<IntakeHistoryPage> createState() => _IntakeHistoryPageState();
}

class _IntakeHistoryPageState extends ConsumerState<IntakeHistoryPage> {
  final _versions = <IntakeVersionSummary>[];
  late final AppLifecycleListener _lifecycle;
  int? _next;
  String? _error;
  int _generation = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    unawaited(_load(generation: _generation));
  }

  @override
  void didUpdateWidget(IntakeHistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clientId != oldWidget.clientId) unawaited(_refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _generation++;
      _versions.clear();
      _next = null;
      _error = null;
      _loading = true;
    });
    await _load(generation: _generation);
  }

  Future<void> _load({required int generation, int? before}) async {
    try {
      final result = await ref
          .read(intakeHistoryRepositoryProvider)
          .listVersions(widget.clientId, before: before);
      if (!mounted || generation != _generation) return;
      setState(() {
        _versions.addAll(result.versions);
        _next = result.nextBefore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _versions.clear();
        _next = null;
        _loading = false;
        _error = error is ClientIntakeException
            ? error.message
            : 'Could not load intake history.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Intake history')),
    body: SafeArea(top: false, child: _buildResults(context)),
  );

  Widget _buildResults(BuildContext context) {
    if (_loading && _versions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              TextButton(onPressed: _refresh, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_versions.isEmpty)
            const Center(
              child: Text('No intake versions have been submitted yet.'),
            ),
          for (final entry in _versions)
            Card(
              child: ListTile(
                title: Text('Version ${entry.version}'),
                subtitle: entry.submittedAt == null
                    ? null
                    : Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(entry.submittedAt!.toLocal()),
                      ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await widget.openVersion(context, entry.version);
                  if (mounted) await _refresh();
                },
              ),
            ),
          if (_next case final cursor?)
            TextButton(
              onPressed: _loading
                  ? null
                  : () {
                      setState(() => _loading = true);
                      unawaited(_load(generation: _generation, before: cursor));
                    },
              child: Text(_loading ? 'Loading versions…' : 'Load more'),
            ),
        ],
      ),
    );
  }
}
