import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/audit_log_entity.dart';
import '../../domain/usecases/get_audit_logs_usecase.dart';
import 'client_list_controller.dart';

class AuditLogState {
  final List<AuditLogEntity> logs;
  final bool isLoading;
  final String? errorMessage;

  const AuditLogState({
    this.logs = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  AuditLogState copyWith({
    List<AuditLogEntity>? logs,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuditLogState(
      logs: logs ?? this.logs,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuditLogController extends Notifier<AuditLogState> {
  late final GetAuditLogsUseCase _getLogs;

  @override
  AuditLogState build() {
    final repo = ref.watch(adminRepositoryProvider);
    _getLogs = GetAuditLogsUseCase(repo);
    _load();
    return const AuditLogState(isLoading: true);
  }

  Future<void> _load() async {
    try {
      final logs = await _getLogs();
      state = state.copyWith(logs: logs, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }
}

final auditLogControllerProvider =
    NotifierProvider<AuditLogController, AuditLogState>(
  AuditLogController.new,
);
