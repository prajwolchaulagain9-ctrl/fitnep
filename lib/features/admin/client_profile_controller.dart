import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/client_entity.dart';
import 'data/audit_log_entity.dart';
import 'data/get_client_by_id_usecase.dart';
import 'data/deactivate_client_usecase.dart';
import 'data/get_audit_logs_usecase.dart';
import 'data/client_assignment_repository.dart';
import 'data/staff_account_repository.dart';
import 'data/staff_account_entity.dart';
import '../authentication/authentication_controller.dart';
import 'client_list_controller.dart';
import '../../app/routes/route_access_gate.dart';

class DietitianAssignmentOption {
  const DietitianAssignmentOption({
    required this.dietitian,
    required this.currentClientCount,
  });

  final StaffAccount dietitian;
  final int currentClientCount;

  String get clientCountLabel => currentClientCount == 1
      ? '1 current client'
      : '$currentClientCount current clients';
}

final activeDietitiansProvider =
    FutureProvider.autoDispose<List<DietitianAssignmentOption>>((ref) async {
      final keepAlive = ref.keepAlive();
      try {
        final user = await ref.watch(authenticationStateProvider.future);
        if (user == null) {
          throw const StaffAccountFailure('Sign in to load dietitians.');
        }
        final assignment = ref.watch(clientAssignmentRepositoryProvider);
        final repository = ref.watch(staffAccountRepositoryProvider(user.uid));
        final dietitians = <StaffAccount>[];
        String? cursor;
        final seen = <String?>{null};
        do {
          final page = await repository.list(cursor);
          dietitians.addAll(
            page.items.where(
              (account) =>
                  account.role == StaffRole.dietitian && account.isActive,
            ),
          );
          cursor = page.nextCursor;
        } while (cursor != null && seen.add(cursor));
        dietitians.sort(
          (left, right) => left.displayName.compareTo(right.displayName),
        );
        final counts = await assignment.dietitianClientCounts();
        return dietitians
            .map(
              (dietitian) => DietitianAssignmentOption(
                dietitian: dietitian,
                currentClientCount: counts[dietitian.uid] ?? 0,
              ),
            )
            .toList(growable: false);
      } finally {
        keepAlive.close();
      }
    });

// ── State ──────────────────────────────────────────────────────────────────

class ClientProfileState {
  final ClientEntity? client;
  final List<AuditLogEntity> auditLogs;
  final bool isLoading;
  final bool isDeactivating;
  final bool isCheckingAssignmentEligibility;
  final bool canAssignClient;
  final bool isAssigning;
  final String? packageStatus;
  final String? assignmentMessage;
  final String? errorMessage;
  final String? successMessage;

  const ClientProfileState({
    this.client,
    this.auditLogs = const [],
    this.isLoading = false,
    this.isDeactivating = false,
    this.isCheckingAssignmentEligibility = true,
    this.canAssignClient = false,
    this.isAssigning = false,
    this.packageStatus,
    this.assignmentMessage,
    this.errorMessage,
    this.successMessage,
  });

  ClientProfileState copyWith({
    ClientEntity? client,
    List<AuditLogEntity>? auditLogs,
    bool? isLoading,
    bool? isDeactivating,
    bool? isCheckingAssignmentEligibility,
    bool? canAssignClient,
    bool? isAssigning,
    String? packageStatus,
    String? assignmentMessage,
    bool clearAssignmentMessage = false,
    String? errorMessage,
    String? successMessage,
  }) {
    return ClientProfileState(
      client: client ?? this.client,
      auditLogs: auditLogs ?? this.auditLogs,
      isLoading: isLoading ?? this.isLoading,
      isDeactivating: isDeactivating ?? this.isDeactivating,
      isCheckingAssignmentEligibility:
          isCheckingAssignmentEligibility ??
          this.isCheckingAssignmentEligibility,
      canAssignClient: canAssignClient ?? this.canAssignClient,
      isAssigning: isAssigning ?? this.isAssigning,
      packageStatus: packageStatus ?? this.packageStatus,
      assignmentMessage: clearAssignmentMessage
          ? null
          : assignmentMessage ?? this.assignmentMessage,
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
  late final ClientAssignmentRepository _assignmentRepository;

  @override
  ClientProfileState build() {
    final repo = ref.watch(adminRepositoryProvider);
    _getClientById = GetClientByIdUseCase(repo);
    _deactivateClient = DeactivateClientUseCase(repo);
    _getLogsForClient = GetAuditLogsForClientUseCase(repo);
    _assignmentRepository = ref.watch(clientAssignmentRepositoryProvider);
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
      await _loadAssignmentEligibility();
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> _loadAssignmentEligibility() async {
    state = state.copyWith(isCheckingAssignmentEligibility: true);
    try {
      final eligibility = await _assignmentRepository.eligibility(_clientId);
      state = state.copyWith(
        isCheckingAssignmentEligibility: false,
        canAssignClient: eligibility.canAssign,
        packageStatus: eligibility.packageStatus,
        assignmentMessage: eligibility.message,
        clearAssignmentMessage: eligibility.message == null,
      );
    } on ClientAssignmentFailure catch (error) {
      state = state.copyWith(
        isCheckingAssignmentEligibility: false,
        canAssignClient: false,
        assignmentMessage: error.message,
      );
    }
  }

  Future<bool> assignDietitian(StaffAccount dietitian) async {
    final client = state.client;
    if (client == null || state.isAssigning) return false;
    if (!state.canAssignClient) {
      state = state.copyWith(
        errorMessage:
            state.assignmentMessage ?? inactivePackageAssignmentMessage,
      );
      return false;
    }
    state = state.copyWith(isAssigning: true);
    try {
      await _assignmentRepository.assign(client.id, dietitian.uid);
      final updated = client.copyWith(
        assignedDietitianId: dietitian.uid,
        assignedDietitianName: dietitian.displayName,
      );
      state = state.copyWith(
        client: updated,
        isAssigning: false,
        successMessage: 'Client assigned successfully.',
      );
      ref.read(clientListControllerProvider.notifier).refreshClient(updated);
      ref.invalidate(activeDietitiansProvider);
      return true;
    } on ClientAssignmentFailure catch (error) {
      await _loadAssignmentEligibility();
      state = state.copyWith(isAssigning: false, errorMessage: error.message);
      return false;
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
        adminId: ref.read(routeSessionProvider).requireValue!.uid,
        adminName: '',
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
        ref.read(routeSessionProvider).requireValue!.uid,
        '',
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
    state = state.copyWith();
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
