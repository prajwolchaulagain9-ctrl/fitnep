import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/package_history_entity.dart';
import '../../domain/repositories/package_repository.dart';
import 'package_management_controller.dart';

class PackageHistoryState {
  final List<PackageHistoryEntity> history;
  final bool isLoading;
  final String? errorMessage;

  const PackageHistoryState({
    this.history = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  PackageHistoryState copyWith({
    List<PackageHistoryEntity>? history,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PackageHistoryState(
      history: history ?? this.history,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PackageHistoryController extends Notifier<PackageHistoryState> {
  late PackageRepository _repository;

  @override
  PackageHistoryState build() {
    _repository = ref.watch(packageRepositoryProvider);
    Future<void>.microtask(refresh);
    return const PackageHistoryState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final history = await _repository.getPackageHistory();
      state = state.copyWith(
        history: history,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }
}

final packageHistoryControllerProvider =
    NotifierProvider<PackageHistoryController, PackageHistoryState>(
      PackageHistoryController.new,
    );
