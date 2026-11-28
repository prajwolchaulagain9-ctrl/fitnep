import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/wellness_illustration.dart';
import '../../authorization/data/account.dart';
import '../../authorization/data/authorization_repository.dart';
import '../../health_assessment/data/client_intake_form.dart';
import '../../health_assessment/widgets/intake_form_fields.dart';
import '../data/client_onboarding_status.dart';

class ClientOnboardingPage extends ConsumerWidget {
  const ClientOnboardingPage({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = clientOnboardingProgressProvider(clientId);
    return ref
        .watch(progress)
        .when(
          loading: () => const AppPage(
            title: 'Set up FitNEP',
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => AppPage(
            title: 'Set up FitNEP',
            child: Column(
              children: [
                Text(_onboardingError(error), textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => ref.invalidate(progress),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
          data: (saved) => _OnboardingJourney(
            key: ValueKey(clientId),
            clientId: clientId,
            saved: saved,
          ),
        );
  }
}

enum _Step { welcome, measurements, next }

class _OnboardingJourney extends ConsumerStatefulWidget {
  const _OnboardingJourney({
    super.key,
    required this.clientId,
    required this.saved,
  });

  final String clientId;
  final ClientOnboardingProgress saved;

  @override
  ConsumerState<_OnboardingJourney> createState() => _OnboardingJourneyState();
}

class _OnboardingJourneyState extends ConsumerState<_OnboardingJourney> {
  final _form = GlobalKey<FormState>();
  late final Map<IntakeField, TextEditingController> _measurements;
  late final bool _resuming;
  late final bool _completed;
  late _Step _step;
  bool _saving = false;
  bool _showValidation = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = widget.saved;
    _resuming = saved.status == ClientOnboardingStatus.skipped;
    _completed = saved.status == ClientOnboardingStatus.completed;
    _step = _completed
        ? _Step.next
        : saved.heightCm != null || saved.weightKg != null || _resuming
        ? _Step.measurements
        : _Step.welcome;
    _measurements = {
      IntakeField.height: TextEditingController(
        text: saved.heightCm?.toString(),
      ),
      IntakeField.weight: TextEditingController(
        text: saved.weightKg?.toString(),
      ),
    };
  }

  @override
  void dispose() {
    for (final controller in _measurements.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _answer(IntakeField field) => _measurements[field]!.text.trim();

  Future<ClientOnboardingStatus?> _save(ClientOnboardingStatus status) async {
    if (_saving) return null;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await ref
          .read(authorizationRepositoryProvider)
          .request(
            'profile/me/onboarding',
            method: 'PUT',
            data: {
              'expected_client_id': widget.clientId,
              'status': switch (status) {
                ClientOnboardingStatus.pending => 'draft',
                ClientOnboardingStatus.skipped => 'skipped',
                ClientOnboardingStatus.completed => 'completed',
              },
              'heightCm': ?IntakeField.height.measurement(
                _answer(IntakeField.height),
              ),
              'weightKg': ?IntakeField.weight.measurement(
                _answer(IntakeField.weight),
              ),
            },
          );
      if (!mounted) return null;
      final result = ClientOnboardingProgress.fromJson(response['onboarding']);
      if (result.status.index < status.index) {
        throw const FormatException('Unexpected onboarding status.');
      }
      return result.status;
    } catch (error) {
      if (mounted) {
        setState(() => _error = _onboardingError(error, saving: true));
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(_Step step) => setState(() {
    _step = step;
    _showValidation = false;
    _error = null;
  });

  Future<void> _review() async {
    setState(() => _showValidation = true);
    if (!_form.currentState!.validate()) return;
    final saved = await _save(
      _resuming
          ? ClientOnboardingStatus.skipped
          : ClientOnboardingStatus.pending,
    );
    if (saved == null || !mounted) return;
    if (saved == ClientOnboardingStatus.completed) {
      _leave();
    } else {
      _show(_Step.next);
      ref.invalidate(clientOnboardingProgressProvider(widget.clientId));
    }
  }

  Future<void> _finish(ClientOnboardingStatus status) async {
    if (_completed || (await _save(status) != null && mounted)) _leave();
  }

  void _leave() {
    final router = GoRouter.of(context);
    ref.invalidate(clientOnboardingProgressProvider(widget.clientId));
    if (_resuming) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(AppRoutes.clientHome);
      }
    } else {
      router.go(AppRoutes.clientPackages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmi = _step == _Step.next
        ? intakeBmi(_answer(IntakeField.height), _answer(IntakeField.weight))
        : null;
    final (title, description) = switch (_step) {
      _Step.welcome => (
        'A little about you',
        'Start with your height and weight before you explore FitNEP packages. You can also finish later from Home.',
      ),
      _Step.measurements => (
        'What are your height and weight?',
        'Enter your current measurements to see your body mass index (BMI).',
      ),
      _Step.next => (
        'Your starting point is ready',
        _resuming
            ? 'These measurements can help you get started on your health intake.'
            : 'You can now compare FitNEP packages and choose the support you want.',
      ),
    };
    final (label, next) = switch (_step) {
      _Step.welcome => ('Get started', () => _show(_Step.measurements)),
      _Step.measurements => ('Review setup', _review),
      _Step.next => (
        _resuming ? 'Finish setup' : 'Explore packages',
        () => _finish(ClientOnboardingStatus.completed),
      ),
    };

    return AppPage(
      key: ValueKey(_step),
      title: 'Set up FitNEP',
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Step ${_step.index + 1} of ${_Step.values.length}',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_step.index + 1) / _Step.values.length,
            semanticsLabel: 'Setup progress',
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
          const SizedBox(height: 24),
          if (_step == _Step.welcome) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: WellnessIllustration(
                  scene: WellnessScene.movement,
                  size: 152,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineLarge),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          if (_step == _Step.measurements)
            Form(
              key: _form,
              autovalidateMode: _showValidation
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              child: IntakeFormFields(
                controllers: _measurements,
                step: IntakeStep.measurements,
                enabled: !_saving,
                onChanged: (_) => setState(() => _error = null),
                validator: (field) =>
                    validateIntakeField(field, _answer(field), complete: true),
              ),
            ),
          if (bmi != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('Height ${_answer(IntakeField.height)} cm'),
                Text('Weight ${_answer(IntakeField.weight)} kg'),
              ],
            ),
            const SizedBox(height: 12),
            BmiPreviewCard(bmi: bmi),
          ],
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _saving ? null : next,
            icon: const Icon(Icons.arrow_forward_rounded),
            iconAlignment: IconAlignment.end,
            label: Text(_saving ? 'Saving…' : label),
          ),
          if (!_completed)
            Wrap(
              alignment: _step == _Step.welcome
                  ? WrapAlignment.center
                  : WrapAlignment.spaceBetween,
              children: [
                if (_step != _Step.welcome)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _show(_Step.values[_step.index - 1]),
                    child: const Text('Back'),
                  ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => _finish(ClientOnboardingStatus.skipped),
                  child: const Text('Skip for now'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

String _onboardingError(Object error, {bool saving = false}) => switch (error) {
  AuthorizationFailure(:final message) => message,
  _ when saving => 'Could not save your setup. Please try again.',
  _ => 'Could not open your setup. Please try again.',
};
