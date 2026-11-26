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
  const IntakeEditorPage({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<IntakeEditorPage> createState() => _IntakeEditorPageState();
}

class _IntakeEditorPageState extends ConsumerState<IntakeEditorPage> {
  final _form = GlobalKey<FormState>();
  final _controllers = {
    for (final field in IntakeField.values) field: TextEditingController(),
  };
  late final AppLifecycleListener _lifecycle;
  IntakeFormWorkspace? _workspace;
  IntakeFormWorkspace? _newerWorkspace;
  Timer? _guardianTimer;
  String? _requestId;
  String? _loadError;
  String? _writeError;
  bool _checking = true;
  bool _saving = false;
  bool _completeValidation = false;
  bool _guardianConfirmed = false;
  bool _guardianOpen = false;
  bool _guardianDismissed = false;

  IntakeWorkspaceRepository get _repository =>
      ref.read(intakeWorkspaceRepositoryProvider);
  Map<IntakeField, String> get _answers => {
    for (final entry in _controllers.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  };
  bool get _hasEdits =>
      _workspace != null && !mapEquals(_workspace!.answers, _answers);
  bool get _needsGuardian =>
      !_guardianConfirmed && needsIntakeGuardian(_answers, DateTime.now());

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
    _guardianTimer?.cancel();
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
            fresh.membershipActive &&
            !mapEquals(fresh.answers, _answers)) {
          if (previous.version != fresh.version ||
              previous.draftRevision != fresh.draftRevision) {
            _newerWorkspace = fresh;
          } else {
            _workspace = fresh;
            _newerWorkspace = null;
          }
          _guardianConfirmed = _guardianConfirmed || fresh.guardianConfirmed;
        } else {
          _applyWorkspace(fresh);
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
    _guardianConfirmed = workspace.guardianConfirmed;
    _guardianDismissed = false;
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
    _guardianConfirmed = false;
    _requestId = null;
    _writeAnswers({});
  }

  void _resolveNewerWorkspace({required bool keepEdits}) {
    final latest = _newerWorkspace!;
    final original = _workspace!.answers;
    final edited = _answers;
    final needsSavedGuardian = _guardianConfirmed;
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
        _guardianConfirmed = needsSavedGuardian || latest.guardianConfirmed;
      }
    });
  }

  void _answerChanged(IntakeField field) {
    setState(() {
      _requestId = null;
      _writeError = null;
    });
    if (field != IntakeField.age && field != IntakeField.dateOfBirth) return;
    _guardianTimer?.cancel();
    if (!_needsGuardian) {
      _guardianDismissed = false;
    } else if (!_guardianDismissed) {
      _guardianTimer = Timer(const Duration(milliseconds: 450), () {
        if (mounted && !_saving && !_checking && _needsGuardian) {
          unawaited(_confirmGuardian());
        }
      });
    }
  }

  Future<bool> _confirmGuardian() async {
    if (!_needsGuardian) return true;
    if (_guardianOpen) return false;
    _guardianOpen = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Parent or guardian consent'),
        content: const Text(
          'If you are under 18, ask a parent or guardian to review the FitNEP '
          'Privacy Policy and confirm that you have their permission to '
          'provide your health information.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => dialogContext.pushNamed(AppRoutes.privacyPolicy),
            child: const Text('Read privacy policy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm permission'),
          ),
        ],
      ),
    );
    _guardianOpen = false;
    if (!mounted) return false;
    if (accepted == true) {
      setState(() {
        _guardianConfirmed = true;
        _requestId = null;
      });
    } else {
      _guardianDismissed = true;
    }
    return accepted == true;
  }

  Future<void> _save({required bool submit}) async {
    final base = _workspace;
    if (base == null ||
        !base.membershipActive ||
        _checking ||
        _saving ||
        _newerWorkspace != null) {
      return;
    }
    _completeValidation = submit;
    if (_form.currentState?.validate() != true) {
      setState(() => _writeError = 'Check the highlighted fields.');
      return;
    }
    _guardianTimer?.cancel();
    if (!await _confirmGuardian() ||
        !mounted ||
        _checking ||
        _saving ||
        _workspace != base ||
        _newerWorkspace != null) {
      return;
    }
    final change = (
      answers: _answers,
      version: base.version,
      draftRevision: base.draftRevision,
      guardianConfirmed: _guardianConfirmed,
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
      if (!mounted) return;
      setState(() => _applyWorkspace(saved));
      _announce(
        submit
            ? (saved.version == base.version + 1
                  ? 'Intake submitted. Your care team can review it.'
                  : 'Showing your latest saved intake.')
            : 'Draft saved.',
      );
    } catch (error) {
      if (!mounted) return;
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _announce(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

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
            ],
          ),
        ),
      );
    }
    final workspace = _workspace!;
    if (!workspace.membershipActive) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'An active membership is required to edit your intake.',
                textAlign: TextAlign.center,
              ),
              TextButton(
                onPressed: () async {
                  await context.push(AppRoutes.clientMembership);
                  if (mounted) await _load();
                },
                child: const Text('View membership'),
              ),
            ],
          ),
        ),
      );
    }
    final latest = workspace.latest;
    final pending = latest?.status == ClientIntakeStatus.informationRequested;
    final enabled = !_saving && _newerWorkspace == null;
    final canSubmit =
        enabled && (latest == null || workspace.draftRevision > 0 || _hasEdits);
    return Form(
      key: _form,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
              controllers: _controllers,
              enabled: enabled,
              onChanged: _answerChanged,
              validator: (field) => validateIntakeField(
                field,
                _answers,
                today: DateTime.now(),
                complete: _completeValidation,
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
            OutlinedButton(
              onPressed:
                  enabled &&
                      (_hasEdits ||
                          (_guardianConfirmed && !workspace.guardianConfirmed))
                  ? () => _save(submit: false)
                  : null,
              child: const Text('Save draft'),
            ),
            FilledButton(
              onPressed: canSubmit ? () => _save(submit: true) : null,
              child: Text(
                latest == null ? 'Submit intake' : 'Submit updated intake',
              ),
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
