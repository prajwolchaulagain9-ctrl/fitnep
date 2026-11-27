import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/app_routes.dart';
import '../../data/datasources/client_intake_remote_datasource.dart';
import '../../data/repositories/intake_workspace_repository.dart';
import '../../domain/entities/client_intake.dart';
import '../../domain/entities/client_intake_form.dart';
import '../widgets/intake_form_fields.dart';

class IntakeEditorPage extends ConsumerStatefulWidget {
  const IntakeEditorPage({
    super.key,
    required this.clientId,
    this.onboarding = false,
  });

  final String clientId;
  final bool onboarding;

  @override
  ConsumerState<IntakeEditorPage> createState() => _IntakeEditorPageState();
}

class _IntakeEditorPageState extends ConsumerState<IntakeEditorPage> {
  final _controllers = {
    for (final field in IntakeField.values) field: TextEditingController(),
  };
  late final AppLifecycleListener _lifecycle;
  IntakeFormWorkspace? _workspace;
  IntakeFormWorkspace? _newerWorkspace;
  String? _requestId;
  String? _loadError;
  String? _writeError;
  bool _checking = true;
  bool _saving = false;
  IntakeStep _step = IntakeStep.measurements;
  bool? _showValidation;

  IntakeWorkspaceRepository get _repository =>
      ref.read(intakeWorkspaceRepositoryProvider);
  Map<IntakeField, String> get _answers => {
    for (final entry in _controllers.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  };
  bool get _hasEdits =>
      _workspace != null && !mapEquals(_workspace!.answers, _answers);
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!_saving && !_checking) unawaited(_load());
      },
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _checking = true;
      _loadError = null;
    });
    try {
      final fresh = await _repository.load(widget.clientId);
      if (!mounted) return;
      setState(() {
        final previous = _workspace;
        if (previous != null &&
            _hasEdits &&
            !mapEquals(fresh.answers, _answers)) {
          if (previous.version != fresh.version ||
              previous.draftRevision != fresh.draftRevision) {
            _newerWorkspace = fresh;
          } else {
            _workspace = fresh;
            _newerWorkspace = null;
          }
        } else {
          _applyWorkspace(fresh);
          if (previous == null && fresh.draftRevision > 0) {
            _step = IntakeStep.values.firstWhere(
              (step) => _stepHasErrors(step, complete: true),
              orElse: () => IntakeStep.food,
            );
          }
        }
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_accessDenied(error)) _forgetIntake();
        _checking = false;
        _loadError = _errorMessage(error);
      });
    }
  }

  void _applyWorkspace(IntakeFormWorkspace workspace) {
    _workspace = workspace;
    _newerWorkspace = null;
    _requestId = null;
    _writeError = null;
    _writeAnswers(workspace.answers);
  }

  void _writeAnswers(Map<IntakeField, String> answers) {
    for (final entry in _controllers.entries) {
      final value = answers[entry.key] ?? '';
      if (entry.value.text != value) entry.value.text = value;
    }
  }

  void _forgetIntake() {
    _workspace = null;
    _newerWorkspace = null;
    _requestId = null;
    _writeAnswers({});
  }

  void _resolveNewerWorkspace({required bool keepEdits}) {
    final latest = _newerWorkspace!;
    final original = _workspace!.answers;
    final edited = _answers;
    setState(() {
      _applyWorkspace(latest);
      if (keepEdits) {
        _writeAnswers({
          for (final field in IntakeField.values)
            if (edited[field] != original[field])
              field: edited[field] ?? ''
            else if (latest.answers.containsKey(field))
              field: latest.answers[field]!,
        });
      }
    });
  }

  void _answerChanged(IntakeField field) {
    setState(() {
      _requestId = null;
      _writeError = null;
    });
  }

  bool _stepHasErrors(IntakeStep step, {required bool complete}) {
    final answers = _answers;
    return step.fields.any(
      (field) =>
          validateIntakeField(
            field,
            answers[field] ?? '',
            complete: complete,
          ) !=
          null,
    );
  }

  void _showErrors(IntakeStep step, {required bool complete}) {
    setState(() {
      _step = step;
      _showValidation = complete;
      _writeError = 'Check the highlighted fields.';
    });
  }

  void _goToStep(IntakeStep step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _showValidation = null;
      _writeError = null;
    });
  }

  Future<void> _next() async {
    if (_stepHasErrors(_step, complete: true)) {
      _showErrors(_step, complete: true);
      return;
    }
    final next = IntakeStep.values[_step.index + 1];
    if (!_hasEdits || await _save(submit: false, announce: false)) {
      if (mounted) _goToStep(next);
    }
  }

  void _finishOnboarding() => context.go(AppRoutes.clientHome);

  Future<void> _saveAndLeave() async {
    if (!_hasEdits || await _save(submit: false, announce: false)) {
      if (mounted) _finishOnboarding();
    }
  }

  Future<bool> _save({required bool submit, bool announce = true}) async {
    final base = _workspace;
    if (base == null ||
        !base.profileReady ||
        _checking ||
        _saving ||
        _newerWorkspace != null) {
      return false;
    }
    for (final step in IntakeStep.values) {
      if (_stepHasErrors(step, complete: submit)) {
        _showErrors(step, complete: submit);
        return false;
      }
    }
    FocusScope.of(context).unfocus();
    final change = (
      answers: _answers,
      version: base.version,
      draftRevision: base.draftRevision,
    );
    setState(() {
      _saving = true;
      _writeError = null;
    });
    try {
      final saved = submit
          ? await _repository.submit(
              widget.clientId,
              change,
              _requestId ??= _newRequestId(),
            )
          : await _repository.saveDraft(widget.clientId, change);
      if (!mounted) return false;
      setState(() => _applyWorkspace(saved));
      if (submit && widget.onboarding) _finishOnboarding();
      if (announce) {
        final router = GoRouter.maybeOf(context);
        _announce(
          submit ? 'Health intake submitted.' : 'Draft saved.',
          action: submit && router != null
              ? SnackBarAction(
                  label: 'Review sharing',
                  onPressed: () =>
                      router.push(AppRoutes.clientPrivacyPreferences),
                )
              : null,
        );
      }
      return true;
    } catch (error) {
      if (!mounted) return false;
      if (_accessDenied(error)) {
        setState(() {
          _forgetIntake();
          _loadError = _errorMessage(error);
        });
      } else {
        setState(() => _writeError = _errorMessage(error));
        if (error is ClientIntakeException &&
            error.failure == ClientIntakeFailure.conflict) {
          await _load();
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _announce(String message, {SnackBarAction? action}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message), action: action));

  bool _accessDenied(Object error) =>
      error is ClientIntakeException &&
      (error.failure == ClientIntakeFailure.forbidden ||
          error.failure == ClientIntakeFailure.unauthorized);

  String _errorMessage(Object error) => error is ClientIntakeException
      ? error.message
      : 'Could not open your intake. Please try again.';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Health intake'),
      actions: [
        if (_workspace?.latest != null &&
            !_checking &&
            !_saving &&
            _loadError == null)
          IconButton(
            tooltip: 'Intake history',
            onPressed: () async {
              await context.pushNamed(AppRoutes.ownIntakeHistoryName);
              if (mounted) await _load();
            },
            icon: const Icon(Icons.history),
          ),
      ],
    ),
    body: SafeArea(top: false, child: _buildBody(context)),
  );

  Widget _buildBody(BuildContext context) {
    if (_checking) return const Center(child: CircularProgressIndicator());
    if (_loadError case final message?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              TextButton(onPressed: _load, child: const Text('Try again')),
              if (widget.onboarding && !_hasEdits)
                TextButton(
                  onPressed: _finishOnboarding,
                  child: const Text('Finish later'),
                ),
            ],
          ),
        ),
      );
    }
    final workspace = _workspace!;
    if (!workspace.profileReady) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Save your date of birth in My profile to start your health intake.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await context.push(AppRoutes.ownProfile);
              if (mounted) await _load();
            },
            child: const Text('Open My profile'),
          ),
          if (widget.onboarding)
            TextButton(
              onPressed: _finishOnboarding,
              child: const Text('Finish later'),
            ),
        ],
      );
    }
    final latest = workspace.latest;
    final pending = latest?.status == ClientIntakeStatus.informationRequested;
    final enabled = !_saving && _newerWorkspace == null;
    final canSubmit =
        enabled && (latest == null || workspace.draftRevision > 0 || _hasEdits);
    final lastStep = _step == IntakeStep.food;
    return Form(
      autovalidateMode: _showValidation == null
          ? AutovalidateMode.disabled
          : AutovalidateMode.always,
      child: SingleChildScrollView(
        key: ValueKey(_step),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Step ${_step.index + 1} of ${IntakeStep.values.length}'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_step.index + 1) / IntakeStep.values.length,
              semanticsLabel: 'Health intake progress',
            ),
            const SizedBox(height: 16),
            Text(_step.label, style: Theme.of(context).textTheme.headlineSmall),
            if (latest != null)
              Card(
                child: ListTile(
                  title: Text(
                    pending
                        ? 'Pending information'
                        : 'Submitted version ${latest.version}',
                  ),
                  subtitle: pending && latest.reviewNote != null
                      ? Text(latest.reviewNote!)
                      : null,
                ),
              ),
            if (_newerWorkspace != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The saved intake changed while you were editing.',
                      ),
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () =>
                                _resolveNewerWorkspace(keepEdits: false),
                            child: const Text('Use saved answers'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _resolveNewerWorkspace(keepEdits: true),
                            child: const Text('Keep my edits'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            IntakeFormFields(
              step: _step,
              controllers: _controllers,
              enabled: enabled,
              onChanged: _answerChanged,
              validator: (field) => validateIntakeField(
                field,
                _controllers[field]!.text.trim(),
                complete: _showValidation == true,
              ),
            ),
            if (_writeError case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (_saving) const LinearProgressIndicator(),
            if (lastStep)
              FilledButton(
                onPressed: canSubmit ? () => _save(submit: true) : null,
                child: Text(
                  latest == null ? 'Submit intake' : 'Submit updated intake',
                ),
              )
            else
              FilledButton(
                onPressed: enabled ? _next : null,
                child: const Text('Next'),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                if (_step != IntakeStep.measurements)
                  TextButton(
                    onPressed: enabled
                        ? () => _goToStep(IntakeStep.values[_step.index - 1])
                        : null,
                    child: const Text('Back'),
                  ),
                if (widget.onboarding)
                  TextButton(
                    onPressed: enabled ? _saveAndLeave : null,
                    child: Text(
                      _hasEdits ? 'Save and finish later' : 'Finish later',
                    ),
                  )
                else
                  TextButton(
                    onPressed: enabled && _hasEdits
                        ? () => _save(submit: false)
                        : null,
                    child: const Text('Save draft'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _newRequestId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
