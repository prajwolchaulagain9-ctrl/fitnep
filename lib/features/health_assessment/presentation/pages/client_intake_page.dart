import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../data/datasources/client_intake_remote_datasource.dart';
import '../../domain/entities/client_intake.dart';
import '../controllers/client_intake_controller.dart';
import '../widgets/intake_priority_card.dart';

class ClientIntakePage extends ConsumerWidget {
  const ClientIntakePage({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final intake = ref.watch(clientIntakeProvider(clientId));
    return Scaffold(
      appBar: AppBar(title: const Text('Client intake form')),
      body: SafeArea(
        top: false,
        child: intake.when(
          data: (value) => _IntakeView(intake: value),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _IntakeError(
            error: error,
            onRetry: () => ref.invalidate(clientIntakeProvider(clientId)),
          ),
        ),
      ),
    );
  }
}

class _IntakeView extends StatelessWidget {
  const _IntakeView({required this.intake});

  final ClientIntake intake;

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
