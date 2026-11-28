import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/routes/app_routes.dart';
import '../data/client_intake_remote_datasource.dart';
import '../data/intake_history_repository.dart';
import '../data/client_intake.dart';
import '../client_intake_controller.dart';
import '../widgets/intake_priority_card.dart';

class ClientIntakePage extends ConsumerStatefulWidget {
  const ClientIntakePage({
    super.key,
    required this.clientId,
    required this.viewerId,
    this.readOnly = false,
    this.version,
  });

  final String clientId;
  final String viewerId;
  final bool readOnly;
  final int? version;

  @override
  ConsumerState<ClientIntakePage> createState() => _ClientIntakePageState();
}

class _ClientIntakePageState extends ConsumerState<ClientIntakePage> {
  late final AppLifecycleListener _lifecycleListener;
  bool _isSaving = false;

  FutureProvider<ClientIntake> get _provider => switch (widget.version) {
    final version? => intakeVersionProvider((
      clientId: widget.clientId,
      viewerId: widget.viewerId,
      version: version,
    )),
    _ when widget.readOnly => ownClientIntakeProvider(widget.viewerId),
    _ => clientIntakeProvider((
      clientId: widget.clientId,
      viewerId: widget.viewerId,
    )),
  };

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _reload);
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _reload() => ref.invalidate(_provider);

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(_provider);
    final version = widget.version;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          version != null
              ? 'Intake version $version'
              : widget.readOnly
              ? 'Your intake form'
              : 'Client intake form',
        ),
        actions: [
          if (version == null &&
              intake.hasValue &&
              !intake.isLoading &&
              !intake.hasError)
            IconButton(
              tooltip: 'Intake history',
              icon: const Icon(Icons.history),
              onPressed: () => context.pushNamed(
                widget.readOnly
                    ? AppRoutes.ownIntakeHistoryName
                    : AppRoutes.dietitianIntakeHistoryName,
                pathParameters: {if (!widget.readOnly) 'id': widget.clientId},
              ),
            ),
          IconButton(
            onPressed: _isSaving ? null : _reload,
            tooltip: 'Refresh intake',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: intake.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          data: (value) => _IntakeView(
            intake: value,
            isSaving: _isSaving,
            readOnly: widget.readOnly,
            showingOwnIntake: widget.viewerId == widget.clientId,
            onOpenEditor: widget.readOnly && version == null
                ? () async {
                    await context.pushNamed(AppRoutes.intakeEditorName);
                    if (mounted) _reload();
                  }
                : null,
            onMarkReviewed: () => _markReviewed(value),
            onRequestMissingInformation: () => _requestInformation(
              value,
              ClientIntakeReviewAction.missingInformation,
            ),
            onRequestClarification: () => _requestInformation(
              value,
              ClientIntakeReviewAction.clarificationRequested,
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _IntakeError(error: error, onRetry: _reload),
        ),
      ),
    );
  }

  Future<void> _markReviewed(ClientIntake intake) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mark form as reviewed?'),
        content: const Text(
          'This confirms that the submitted intake information has been reviewed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Mark reviewed'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _saveReview(intake, ClientIntakeReviewAction.reviewed);
    }
  }

  Future<void> _requestInformation(
    ClientIntake intake,
    ClientIntakeReviewAction action,
  ) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _RequestInformationDialog(action: action),
    );
    if (note != null && mounted) await _saveReview(intake, action, note: note);
  }

  Future<void> _saveReview(
    ClientIntake intake,
    ClientIntakeReviewAction action, {
    String? note,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(clientIntakeRepositoryProvider)
          .updateReview(
            clientId: intake.clientId,
            action: action,
            note: note,
            expectedVersion: intake.version,
            expectedReviewRevision: intake.reviewRevision,
          );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == ClientIntakeReviewAction.reviewed
                ? 'Intake form marked as reviewed.'
                : 'Information request saved.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      // The server may have saved the review before the response was lost.
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _IntakeView extends StatelessWidget {
  const _IntakeView({
    required this.intake,
    required this.isSaving,
    required this.showingOwnIntake,
    this.readOnly = false,
    this.onOpenEditor,
    required this.onMarkReviewed,
    required this.onRequestMissingInformation,
    required this.onRequestClarification,
  });

  final ClientIntake intake;
  final bool readOnly;
  final bool isSaving;
  final bool showingOwnIntake;
  final VoidCallback? onOpenEditor;
  final VoidCallback onMarkReviewed;
  final VoidCallback onRequestMissingInformation;
  final VoidCallback onRequestClarification;

  @override
  Widget build(BuildContext context) {
    final sections = showingOwnIntake
        ? [
            for (final section in intake.sections)
              if (section.fields.where(_showOwnField).toList() case final fields
                  when fields.isNotEmpty)
                ClientIntakeSection(title: section.title, fields: fields),
          ]
        : intake.sections;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _ReviewStatusCard(intake: intake),
        if (onOpenEditor case final edit?) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: edit,
            icon: const Icon(Icons.edit_outlined),
            label: Text(
              intake.status == ClientIntakeStatus.informationRequested
                  ? 'Respond to request'
                  : 'Edit intake',
            ),
          ),
        ],
        const SizedBox(height: 16),
        IntakePriorityCard(
          title: 'Allergies',
          values: intake.allergies,
          icon: Icons.warning_amber_rounded,
          color: AppColors.error,
        ),
        const SizedBox(height: 12),
        IntakePriorityCard(
          title: 'Medical conditions',
          values: intake.medicalConditions,
          icon: Icons.medical_information_outlined,
          color: AppColors.warning,
        ),
        const SizedBox(height: 24),
        Text('Complete intake', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(_dateSummary, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        for (final section in sections) ...[
          _IntakeSectionCard(section: section),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        if (!readOnly)
          _ReviewActionsCard(
            isSaving: isSaving,
            onMarkReviewed: onMarkReviewed,
            onRequestMissingInformation: onRequestMissingInformation,
            onRequestClarification: onRequestClarification,
          ),
      ],
    );
  }

  // Keep historical measurements available to care-team reviewers.
  static bool _showOwnField(ClientIntakeField field) =>
      !_extraMeasurement.hasMatch(field.label.trim());

  static final _extraMeasurement = RegExp(
    r'^(waist|hips?|chest|feet|foot)( (size|circumference))?( \(?cm\)?)?$',
    caseSensitive: false,
  );

  String get _dateSummary {
    final date = intake.updatedAt ?? intake.submittedAt;
    if (date == null) return 'Submitted intake information';
    final prefix = intake.updatedAt == null ? 'Submitted' : 'Last updated';
    return '$prefix ${DateFormat('dd MMM yyyy, h:mm a').format(date)}';
  }
}

class _ReviewStatusCard extends StatelessWidget {
  const _ReviewStatusCard({required this.intake});

  final ClientIntake intake;

  @override
  Widget build(BuildContext context) {
    final (
      title,
      description,
      icon,
      color,
      background,
    ) = switch (intake.status) {
      ClientIntakeStatus.reviewed => (
        'Reviewed',
        'The intake form has been reviewed.',
        Icons.check_circle_outline_rounded,
        AppColors.success,
        AppColors.statusActiveContainer,
      ),
      ClientIntakeStatus.informationRequested => (
        'Pending Information',
        _requestDescription,
        Icons.info_outline_rounded,
        AppColors.warning,
        AppColors.statusPendingContainer,
      ),
      ClientIntakeStatus.submitted => (
        'Awaiting review',
        'The submitted information is awaiting your care team’s review.',
        Icons.schedule_rounded,
        AppColors.info,
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.statusSurface(context, color, background),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: color),
                ),
                const SizedBox(height: 4),
                Text(description),
                if (intake.reviewNote case final note?) ...[
                  const SizedBox(height: 8),
                  Text(
                    note,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
                if (intake.reviewUpdatedAt case final date?) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Updated ${DateFormat('dd MMM yyyy, h:mm a').format(date)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _requestDescription => switch (intake.reviewAction) {
    ClientIntakeReviewAction.clarificationRequested =>
      'Clarification has been requested from the client.',
    _ => 'Missing information has been requested from the client.',
  };
}

class _ReviewActionsCard extends StatelessWidget {
  const _ReviewActionsCard({
    required this.isSaving,
    required this.onMarkReviewed,
    required this.onRequestMissingInformation,
    required this.onRequestClarification,
  });

  final bool isSaving;
  final VoidCallback onMarkReviewed;
  final VoidCallback onRequestMissingInformation;
  final VoidCallback onRequestClarification;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Review form', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Save one outcome for this intake form.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isSaving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: isSaving ? null : onMarkReviewed,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Mark as reviewed'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isSaving ? null : onRequestMissingInformation,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Request missing information'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: isSaving ? null : onRequestClarification,
              icon: const Icon(Icons.help_outline_rounded),
              label: const Text('Request clarification'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestInformationDialog extends StatefulWidget {
  const _RequestInformationDialog({required this.action});

  final ClientIntakeReviewAction action;

  @override
  State<_RequestInformationDialog> createState() =>
      _RequestInformationDialogState();
}

class _RequestInformationDialogState extends State<_RequestInformationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clarification =
        widget.action == ClientIntakeReviewAction.clarificationRequested;
    return AlertDialog(
      title: Text(
        clarification ? 'Request clarification' : 'Request missing information',
      ),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: clarification
                ? 'What needs clarification?'
                : 'What information is missing?',
            alignLabelWithHint: true,
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Describe what the client needs to provide.'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(_controller.text.trim());
          },
          child: const Text('Send request'),
        ),
      ],
    );
  }
}

class _IntakeSectionCard extends StatelessWidget {
  const _IntakeSectionCard({required this.section});

  final ClientIntakeSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(section.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (var index = 0; index < section.fields.length; index++) ...[
              _IntakeFieldRow(field: section.fields[index]),
              if (index < section.fields.length - 1) const Divider(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _IntakeFieldRow extends StatelessWidget {
  const _IntakeFieldRow({required this.field});

  final ClientIntakeField field;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          field.value,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _IntakeError extends StatelessWidget {
  const _IntakeError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final intakeError = error is ClientIntakeException
        ? error as ClientIntakeException
        : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 52),
            const SizedBox(height: 16),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (intakeError?.canRetry ?? true) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
