import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api_client.dart';
import '../../shared/authorization_refresh.dart';
import '../notifications/notification_controller.dart';
import 'data/package_remote_datasource.dart';
import 'data/package_repository_impl.dart';
import 'data/package_entity.dart';
import 'data/package_repository.dart';

final packageRemoteDatasourceProvider = Provider<PackageRemoteDatasource>((
  ref,
) {
  final ApiClient apiClient = ref.watch(apiClientProvider);
  return PackageRemoteDatasourceImpl(apiClient);
});

final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  return PackageRepositoryImpl(ref.watch(packageRemoteDatasourceProvider));
});

// Re-fetch on page entry and after admin mutations; never retain an empty
// catalog across a client/admin account switch.
final activePackagesProvider = FutureProvider.autoDispose<List<PackageEntity>>((
  ref,
) {
  ref.watch(authorizationEpochProvider);
  return ref.watch(packageRepositoryProvider).getActivePackages();
}, retry: (count, error) => null);

class PackageManagementState {
  final List<PackageEntity> packages;
  final bool isLoading;
  final bool isCreating;
  final bool isSaving;
  final String? errorMessage;

  const PackageManagementState({
    this.packages = const [],
    this.isLoading = false,
    this.isCreating = false,
    this.isSaving = false,
    this.errorMessage,
  });

  PackageManagementState copyWith({
    List<PackageEntity>? packages,
    bool? isLoading,
    bool? isCreating,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PackageManagementState(
      packages: packages ?? this.packages,
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class PackageManagementController extends Notifier<PackageManagementState> {
  late PackageRepository _repository;
  int _generation = 0;

  @override
  PackageManagementState build() {
    _generation++;
    _repository = ref.watch(packageRepositoryProvider);
    Future<void>.microtask(refresh);
    return const PackageManagementState(isLoading: true);
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = _generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final packages = await _repository.getPackages();
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        packages: packages,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<PackageEntity> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  }) async {
    final generation = _generation;
    if (state.isCreating) {
      throw const PackageSubmissionInProgressException();
    }
    state = state.copyWith(isCreating: true, clearError: true);
    try {
      final created = await _repository.createPackage(
        requestId: requestId,
        name: name,
        durationMonths: durationMonths,
        price: price,
        featureDescription: featureDescription,
      );
      if (!ref.mounted || generation != _generation) return created;
      ref.invalidate(activePackagesProvider);
      List<PackageEntity> refreshed;
      try {
        refreshed = await _repository.getPackages();
      } catch (_) {
        if (!ref.mounted || generation != _generation) return created;
        refreshed = [
          created,
          ...state.packages.where((item) => item.id != created.id),
        ];
      }
      if (!ref.mounted || generation != _generation) return created;
      state = state.copyWith(
        packages: refreshed,
        isCreating: false,
        isLoading: false,
        clearError: true,
      );
      return created;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(isCreating: false);
      }
      rethrow;
    }
  }

  Future<PackageEntity> updatePackage({
    required String id,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  }) async {
    final generation = _generation;
    if (state.isSaving) throw const PackageSubmissionInProgressException();
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _repository.updatePackage(
        id: id,
        name: name,
        durationMonths: durationMonths,
        price: price,
        featureDescription: featureDescription,
      );
      if (!ref.mounted || generation != _generation) return updated;
      ref.invalidate(activePackagesProvider);
      // Replace the updated package in the list optimistically.
      final updatedList = state.packages
          .map((p) {
            return p.id == updated.id ? updated : p;
          })
          .toList(growable: false);
      state = state.copyWith(
        packages: updatedList,
        isSaving: false,
        clearError: true,
      );
      return updated;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(isSaving: false, errorMessage: error.toString());
      }
      rethrow;
    }
  }

  Future<PackageEntity> setPackageActiveStatus({
    required String id,
    required bool isActive,
  }) async {
    final generation = _generation;
    if (state.isSaving) throw const PackageSubmissionInProgressException();
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _repository.setPackageActiveStatus(
        id: id,
        isActive: isActive,
      );
      if (!ref.mounted || generation != _generation) return updated;
      ref.invalidate(activePackagesProvider);
      final updatedList = state.packages
          .map((p) {
            return p.id == updated.id ? updated : p;
          })
          .toList(growable: false);
      state = state.copyWith(
        packages: updatedList,
        isSaving: false,
        clearError: true,
      );
      return updated;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(isSaving: false, errorMessage: error.toString());
      }
      rethrow;
    }
  }
}

class PackageSubmissionInProgressException implements Exception {
  const PackageSubmissionInProgressException();

  @override
  String toString() => 'A package is already being saved.';
}

final packageManagementControllerProvider =
    NotifierProvider<PackageManagementController, PackageManagementState>(
      PackageManagementController.new,
    );
