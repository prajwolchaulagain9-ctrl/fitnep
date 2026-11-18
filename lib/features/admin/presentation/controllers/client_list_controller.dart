import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/admin_local_datasource.dart';
import '../../data/repositories/admin_repository_impl.dart';
import '../../domain/entities/client_entity.dart';
import '../../domain/usecases/get_all_clients_usecase.dart';

// ── Dependency providers ───────────────────────────────────────────────────

final adminDatasourceProvider = Provider<AdminLocalDatasource>(
  (_) => AdminLocalDatasource(),
);

final adminRepositoryProvider = Provider<AdminRepositoryImpl>((ref) {
  return AdminRepositoryImpl(ref.watch(adminDatasourceProvider));
});

// ── Filter state ───────────────────────────────────────────────────────────

class ClientFilters {
  final Set<String> packages;
  final Set<ClientStatus> statuses;
  final Set<String> dietitians;

  const ClientFilters({
    this.packages = const {},
    this.statuses = const {},
    this.dietitians = const {},
  });

  bool get isEmpty =>
      packages.isEmpty && statuses.isEmpty && dietitians.isEmpty;

  int get activeCount =>
      (packages.isNotEmpty ? 1 : 0) +
      (statuses.isNotEmpty ? 1 : 0) +
      (dietitians.isNotEmpty ? 1 : 0);

  ClientFilters copyWith({
    Set<String>? packages,
    Set<ClientStatus>? statuses,
    Set<String>? dietitians,
  }) {
    return ClientFilters(
      packages: packages ?? this.packages,
      statuses: statuses ?? this.statuses,
      dietitians: dietitians ?? this.dietitians,
    );
  }
}

// ── Client list state ──────────────────────────────────────────────────────

class ClientListState {
  final List<ClientEntity> allClients;
  final List<ClientEntity> filteredClients;
  final String searchQuery;
  final ClientFilters filters;
  final bool isLoading;
  final String? errorMessage;

  const ClientListState({
    this.allClients = const [],
    this.filteredClients = const [],
    this.searchQuery = '',
    this.filters = const ClientFilters(),
    this.isLoading = false,
    this.errorMessage,
  });

  ClientListState copyWith({
    List<ClientEntity>? allClients,
    List<ClientEntity>? filteredClients,
    String? searchQuery,
    ClientFilters? filters,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ClientListState(
      allClients: allClients ?? this.allClients,
      filteredClients: filteredClients ?? this.filteredClients,
      searchQuery: searchQuery ?? this.searchQuery,
      filters: filters ?? this.filters,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  // Computed helpers for filter chips
  Set<String> get availablePackages =>
      allClients.map((c) => c.packageName).toSet();
  Set<String> get availableDietitians =>
      allClients.map((c) => c.assignedDietitianName).toSet();
}

// ── Controller ─────────────────────────────────────────────────────────────

class ClientListController extends Notifier<ClientListState> {
  late final GetAllClientsUseCase _getAllClients;

  @override
  ClientListState build() {
    final repo = ref.watch(adminRepositoryProvider);
    _getAllClients = GetAllClientsUseCase(repo);
    _loadClients();
    return const ClientListState(isLoading: true);
  }

  Future<void> _loadClients() async {
    try {
      final clients = await _getAllClients();
      state = state.copyWith(
        allClients: clients,
        filteredClients: clients,
        isLoading: false,
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _loadClients();
  }

  void updateSearch(String query) {
    state = state.copyWith(searchQuery: query);
    _applyFilters();
  }

  void updateFilters(ClientFilters filters) {
    state = state.copyWith(filters: filters);
    _applyFilters();
  }

  void clearFilters() {
    state = state.copyWith(filters: const ClientFilters(), searchQuery: '');
    _applyFilters();
  }

  void _applyFilters() {
    var result = state.allClients;
    final q = state.searchQuery.toLowerCase().trim();
    if (q.isNotEmpty) {
      result = result.where((c) => c.name.toLowerCase().contains(q)).toList();
    }
    final f = state.filters;
    if (f.packages.isNotEmpty) {
      result = result.where((c) => f.packages.contains(c.packageName)).toList();
    }
    if (f.statuses.isNotEmpty) {
      result = result.where((c) => f.statuses.contains(c.status)).toList();
    }
    if (f.dietitians.isNotEmpty) {
      result = result
          .where((c) => f.dietitians.contains(c.assignedDietitianName))
          .toList();
    }
    state = state.copyWith(filteredClients: result);
  }

  /// Called after a deactivation/reactivation to refresh a single client in the list.
  void refreshClient(ClientEntity updated) {
    final updatedAll = state.allClients.map((c) {
      return c.id == updated.id ? updated : c;
    }).toList();
    state = state.copyWith(allClients: updatedAll);
    _applyFilters();
  }
}

final clientListControllerProvider =
    NotifierProvider<ClientListController, ClientListState>(
      ClientListController.new,
    );
