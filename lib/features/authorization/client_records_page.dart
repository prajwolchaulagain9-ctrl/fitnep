import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes/route_access_gate.dart';
import 'data/authorization_repository.dart';
import '../packages/data/package_repository.dart' show newPackageRequestId;

class ClientRecordsPage extends ConsumerStatefulWidget {
  const ClientRecordsPage({
    required this.clientId,
    this.plansOnly = false,
    super.key,
  });
  final String clientId;
  final bool plansOnly;
  @override
  ConsumerState<ClientRecordsPage> createState() => _ClientRecordsPageState();
}

class _ClientRecordsPageState extends ConsumerState<ClientRecordsPage> {
  static const categories = {
    'nutrition-records': 'Nutrition records',
    'meal-photos': 'Meal photos',
    'progress-photos': 'Progress photos',
    'activity-data': 'Device activity',
    'weight-history': 'Weight history',
  };
  String category = 'nutrition-records';
  late Future<List<_WorkspaceSection>> contents;
  String? error;
  bool saving = false;
  String? _newPlanRequestId;
  String get clientPath => 'clients/${Uri.encodeComponent(widget.clientId)}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final repo = ref.read(authorizationRepositoryProvider);
    contents = Future.wait([
      if (widget.plansOnly)
        Future.value(const _WorkspaceSection([], null))
      else
        _WorkspaceSection.load(
          repo.all(
            category == 'weight-history'
                ? '$clientPath/weight-history'
                : '$clientPath/records/$category',
            'records',
          ),
        ),
      _WorkspaceSection.load(repo.all('$clientPath/diet-plans', 'plans')),
    ]);
  }

  Future<void> _editPlan([Map<String, dynamic>? plan]) async {
    final submission = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _DietPlanEditor(plan: plan),
    );
    if (submission == null || !mounted) return;
    await _savePlan({
      ...submission,
      'draft': true,
      if (plan != null) 'version': plan['version'] ?? 1,
      if (plan == null)
        'request_id': _newPlanRequestId ??= newPackageRequestId(),
    }, plan: plan);
  }

  Future<void> _actOnPlan(Map<String, dynamic> plan, String action) async {
    String? reason;
    if (action == 'return') {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => const _PlanReturnDialog(),
      );
      if (!mounted || reason == null) return;
    }
    await _savePlan({
      'action': action,
      'version': plan['version'] ?? 1,
      'reason': ?reason,
    }, plan: plan);
  }

  Future<void> _savePlan(
    Map<String, dynamic> submission, {
    required Map<String, dynamic>? plan,
  }) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(authorizationRepositoryProvider)
          .request(
            '$clientPath/diet-plans${plan == null ? '' : '/${Uri.encodeComponent(plan['id'] as String)}'}',
            method: plan == null ? 'POST' : 'PATCH',
            data: submission,
          );
      if (mounted) {
        if (plan == null) _newPlanRequestId = null;
        setState(_load);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Diet plan saved.')));
      }
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(routeSessionProvider).value?.role;
    final mayManage = AuthorizationService(role)
        .hasPermission('manage_diet_plans');
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.plansOnly ? 'Review diet plans' : 'Records and diet plans',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: saving ? null : () => setState(_load),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (saving) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
          Expanded(
            child: FutureBuilder(
              future: contents,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(snapshot.error.toString()),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final records = snapshot.data![0].items,
                    plans = snapshot.data![1].items;
                final recordsError = snapshot.data![0].error,
                    plansError = snapshot.data![1].error;
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Diet plans',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        if (mayManage && plansError == null)
                          FilledButton(
                            onPressed: saving ? null : _editPlan,
                            child: const Text('Create plan'),
                          ),
                      ],
                    ),
                    if (plansError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(plansError),
                      ),
                    if (plans.isEmpty && plansError == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('No diet plans have been assigned.'),
                      ),
                    for (final plan in plans) _planCard(plan, role),
                    if (!widget.plansOnly) ...[
                      const SizedBox(height: 24),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Record category',
                        ),
                        items: [
                          for (final entry in categories.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              category = value;
                              _load();
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      if (recordsError != null) Text(recordsError),
                      if (records.isEmpty && recordsError == null)
                        const Text('No records in this category.'),
                      for (final record in records)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record['recorded_at'] as String),
                                for (final entry
                                    in (record['details'] as Map).entries)
                                  Text(
                                    '${entry.key.toString().replaceAll('_', ' ')}: ${entry.value}',
                                  ),
                                if (category.endsWith('photos'))
                                  _ProtectedPhoto(
                                    path:
                                        '$clientPath/records/$category/${Uri.encodeComponent(record['id'] as String)}/photo',
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan, FitNepRole? role) {
    final status = plan['status'] as String? ?? 'published';
    final actions = switch ((role, status)) {
      (FitNepRole.dietitian, 'draft') => const {
        'edit': 'Edit plan',
        'submit': 'Submit for review',
      },
      (FitNepRole.dietitian, 'returned' || 'published') => const {
        'edit': 'Revise plan',
      },
      (FitNepRole.dietitian, 'approved') => const {'publish': 'Publish plan'},
      (FitNepRole.admin, 'submitted') => const {
        'return': 'Return for changes',
        'approve': 'Approve plan',
      },
      _ => const <String, String>{},
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan['title'] as String? ?? 'Diet plan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Version ${plan['version'] ?? 1} • ${status[0].toUpperCase()}${status.substring(1)}',
            ),
            const SizedBox(height: 8),
            Text(plan['description'] as String? ?? ''),
            if (plan['return_reason'] case final String reason) ...[
              const SizedBox(height: 8),
              Text('Changes requested: $reason'),
            ],
            if (actions.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in actions.entries)
                    TextButton(
                      onPressed: saving
                          ? null
                          : () {
                              if (entry.key == 'edit') {
                                _editPlan(plan);
                              } else {
                                _actOnPlan(plan, entry.key);
                              }
                            },
                      child: Text(entry.value),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanReturnDialog extends StatefulWidget {
  const _PlanReturnDialog();

  @override
  State<_PlanReturnDialog> createState() => _PlanReturnDialogState();
}

class _PlanReturnDialogState extends State<_PlanReturnDialog> {
  String reason = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Return for changes'),
    content: TextField(
      autofocus: true,
      maxLength: 500,
      maxLines: 3,
      decoration: const InputDecoration(labelText: 'Changes requested'),
      onChanged: (value) => setState(() => reason = value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: reason.isEmpty ? null : () => Navigator.pop(context, reason),
        child: const Text('Return plan'),
      ),
    ],
  );
}

class _ProtectedPhoto extends ConsumerStatefulWidget {
  const _ProtectedPhoto({required this.path});
  final String path;
  @override
  ConsumerState<_ProtectedPhoto> createState() => _ProtectedPhotoState();
}

class _ProtectedPhotoState extends ConsumerState<_ProtectedPhoto> {
  late Future<Response<List<int>>> photo;
  @override
  void initState() {
    super.initState();
    photo = ref
        .read(authorizationRepositoryProvider)
        .dio
        .get<List<int>>(
          widget.path,
          options: Options(responseType: ResponseType.bytes),
        );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: photo,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text(
          'This photo could not be loaded. Check your permission and connection.',
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(),
        );
      }
      return Image.memory(
        Uint8List.fromList(snapshot.data!.data!),
        height: 220,
        fit: BoxFit.contain,
      );
    },
  );
}

class _DietPlanEditor extends ConsumerStatefulWidget {
  const _DietPlanEditor({this.plan});
  final Map<String, dynamic>? plan;
  @override
  ConsumerState<_DietPlanEditor> createState() => _DietPlanEditorState();
}

class _DietPlanEditorState extends ConsumerState<_DietPlanEditor> {
  final formKey = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: widget.plan?['title'] as String?,
  );
  late final description = TextEditingController(
    text: widget.plan?['description'] as String?,
  );
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthorizationService(ref.watch(routeSessionProvider).value?.role)
        .hasPermission('manage_diet_plans')) {
      return const AlertDialog(
        title: Text('Access denied'),
        content: Text('You do not have permission to access this feature.'),
      );
    }
    return AlertDialog(
      title: Text(widget.plan == null ? 'Create diet plan' : 'Edit diet plan'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Plan title'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a plan title.'
                      : null,
                ),
                TextFormField(
                  controller: description,
                  maxLength: 10000,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Diet plan'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the diet plan.'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(context, <String, dynamic>{
                'title': title.text.trim(),
                'description': description.text.trim(),
              });
            }
          },
          child: const Text('Save plan'),
        ),
      ],
    );
  }
}

class _WorkspaceSection {
  const _WorkspaceSection(this.items, this.error);
  final List<Map<String, dynamic>> items;
  final String? error;
  static Future<_WorkspaceSection> load(
    Future<List<Map<String, dynamic>>> request,
  ) async {
    try {
      return _WorkspaceSection(await request, null);
    } catch (error) {
      return _WorkspaceSection(const [], error.toString());
    }
  }
}
