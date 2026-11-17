import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/client_entity.dart';
import '../../domain/entities/audit_log_entity.dart';
import '../../domain/usecases/get_client_by_id_usecase.dart';
import '../../domain/usecases/deactivate_client_usecase.dart';
import '../../domain/usecases/get_audit_logs_usecase.dart';
import 'client_list_controller.dart';

// ── State ──────────────────────────────────────────────────────────────────

class ClientProfileState {
  final ClientEntity? client;
  final List<AuditLogEntity> auditLogs;
  final bool isLoading;
  final bool isDeactivating;
  final String? errorMessage;
  final String? successMessage;

  const ClientProfileState({
    this.client,
    this.auditLogs = const [],
    this.isLoading = false,
    this.isDeactivating = false,
    this.errorMessage,
    this.successMessage,
  });

  ClientProfileState copyWith({
    ClientEntity? client,
    List<AuditLogEntity>? auditLogs,
    bool? isLoading,
    bool? isDeactivating,
    String? errorMessage,
    String? successMessage,
  }) {
    return ClientProfileState(
      client: client ?? this.client,
      auditLogs: auditLogs ?? this.auditLogs,
      isLoading: isLoading ?? this.isLoading,
      isDeactivating: isDeactivating ?? this.isDeactivating,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

// ── Controller ─────────────────────────────────────────────────────────────
// In Riverpod 3.5, the autoDispose.family builder passes the arg to the
// factory function (Notifier Function(ArgT arg)). So the notifier receives
// the clientId via its constructor and stores it. build() takes no args.

class ClientProfileController extends Notifier<ClientProfileState> {
  final String _clientId;

  ClientProfileController(this._clientId);

  late final GetClientByIdUseCase _getClientById;
  late final DeactivateClientUseCase _deactivateClient;
  late final GetAuditLogsForClientUseCase _getLogsForClient;

  @override
  ClientProfileState build() {
    final repo = ref.watch(adminRepositoryProvider);
    _getClientById = GetClientByIdUseCase(repo);
    _deactivateClient = DeactivateClientUseCase(repo);
    _getLogsForClient = GetAuditLogsForClientUseCase(repo);
    _load();
    return const ClientProfileState(isLoading: true);
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _getClientById(_clientId),
        _getLogsForClient(_clientId),
      ]);
      state = state.copyWith(
        client: results[0] as ClientEntity,
        auditLogs: results[1] as List<AuditLogEntity>,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<bool> deactivateClient(String reason) async {
    final client = state.client;
    if (client == null) return false;
    state = state.copyWith(isDeactivating: true);
    try {
      await _deactivateClient(
        clientId: client.id,
        reason: reason,
        adminId: 'admin_001',
        adminName: 'Admin CEO',
      );
      final updated = await _getClientById(client.id);
      final logs = await _getLogsForClient(client.id);
      state = state.copyWith(
        client: updated,
        auditLogs: logs,
        isDeactivating: false,
        successMessage: 'Client deactivated successfully.',
      );
      ref.read(clientListControllerProvider.notifier).refreshClient(updated);
      return true;
    } catch (e) {
      state = state.copyWith(
        isDeactivating: false,
        errorMessage: 'Failed to deactivate: ${e.toString()}',
      );
      return false;
    }
  }

  Future<bool> reactivateClient() async {
    final client = state.client;
    if (client == null) return false;
    state = state.copyWith(isDeactivating: true);
    try {
      final repo = ref.read(adminRepositoryProvider);
      await repo.reactivateClient(
        client.id,
        'Account reactivated by admin',
        'admin_001',
        'Admin CEO',
      );
      final updated = await _getClientById(client.id);
      final logs = await _getLogsForClient(client.id);
      state = state.copyWith(
        client: updated,
        auditLogs: logs,
        isDeactivating: false,
        successMessage: 'Client reactivated successfully.',
      );
      ref.read(clientListControllerProvider.notifier).refreshClient(updated);
      return true;
    } catch (e) {
      state = state.copyWith(
        isDeactivating: false,
        errorMessage: 'Failed to reactivate: ${e.toString()}',
      );
      return false;
    }
  }

  void clearMessages() {
    // Clears transient snackbar messages from state
    state = ClientProfileState(
      client: state.client,
      auditLogs: state.auditLogs,
      isLoading: state.isLoading,
      isDeactivating: state.isDeactivating,
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────
// The autoDispose.family builder in Riverpod 3.5 passes the arg to the
// factory: NotifierT Function(ArgT arg). So we pass a closure that
// constructs ClientProfileController with the given clientId.

final clientProfileControllerProvider = NotifierProvider.autoDispose
    .family<ClientProfileController, ClientProfileState, String>(
  (arg) => ClientProfileController(arg),
);
