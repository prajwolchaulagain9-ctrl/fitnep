import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/datasources/client_intake_remote_datasource.dart';
import '../../domain/entities/client_intake.dart';
import '../controllers/client_intake_controller.dart';
import '../widgets/intake_priority_card.dart';

class ClientIntakePage extends ConsumerStatefulWidget {
  const ClientIntakePage({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<ClientIntakePage> createState() => _ClientIntakePageState();
}

class _ClientIntakePageState extends ConsumerState<ClientIntakePage> {
  ClientIntake? _savedIntake;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final intake = ref.watch(clientIntakeProvider(widget.clientId));
    return Scaffold(
      appBar: AppBar(title: const Text('Client intake form')),
      body: SafeArea(
        top: false,
        child: intake.when(
          data: (value) => _IntakeView(
            intake: _savedIntake ?? value,
            isSaving: _isSaving,
            onMarkReviewed: _markReviewed,
            onRequestMissingInformation: () => _requestInformation(
              ClientIntakeReviewAction.missingInformation,
            ),
            onRequestClarification: () => _requestInformation(
              ClientIntakeReviewAction.clarificationRequested,
            ),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _IntakeError(
            error: error,
            onRetry: () =>
                ref.invalidate(clientIntakeProvider(widget.clientId)),
          ),
        ),
      ),
    );
  }

  Future<void> _markReviewed() async {
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
    if (confirmed == true) {
      await _saveReview(ClientIntakeReviewAction.reviewed);
    }
  }

  Future<void> _requestInformation(ClientIntakeReviewAction action) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _RequestInformationDialog(action: action),
    );
    if (note != null) await _saveReview(action, note: note);
  }

  Future<void> _saveReview(
    ClientIntakeReviewAction action, {
    String? note,
  }) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final saved = await ref
          .read(clientIntakeRepositoryProvider)
          .updateReview(clientId: widget.clientId, action: action, note: note);
      if (!mounted) return;
      setState(() => _savedIntake = saved);
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
    required this.onMarkReviewed,
    required this.onRequestMissingInformation,
    required this.onRequestClarification,
  });

  final ClientIntake intake;
  final bool isSaving;
  final VoidCallback onMarkReviewed;
  final VoidCallback onRequestMissingInformation;
  final VoidCallback onRequestClarification;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _ReviewStatusCard(intake: intake),
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
        for (final section in intake.sections) ...[
          _IntakeSectionCard(section: section),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        _ReviewActionsCard(
          isSaving: isSaving,
          onMarkReviewed: onMarkReviewed,
          onRequestMissingInformation: onRequestMissingInformation,
          onRequestClarification: onRequestClarification,
        ),
      ],
    );
  }

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
        'More information required',
        _requestDescription,
        Icons.info_outline_rounded,
        AppColors.warning,
        AppColors.statusPendingContainer,
      ),
      ClientIntakeStatus.submitted => (
        'Awaiting review',
        'Review the submitted information and select an action below.',
        Icons.schedule_rounded,
        AppColors.info,
        AppColors.surfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
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
