import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../notifications/presentation/controllers/notification_controller.dart';
import '../../data/datasources/package_remote_datasource.dart';
import '../../data/repositories/package_repository_impl.dart';
import '../../domain/entities/package_entity.dart';
import '../../domain/repositories/package_repository.dart';

final packageRemoteDatasourceProvider = Provider<PackageRemoteDatasource>((
  ref,
) {
  final ApiClient apiClient = ref.watch(apiClientProvider);
  return PackageRemoteDatasourceImpl(apiClient);
});

final packageRepositoryProvider = Provider<PackageRepository>((ref) {
  return PackageRepositoryImpl(ref.watch(packageRemoteDatasourceProvider));
});

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

  @override
  PackageManagementState build() {
    _repository = ref.watch(packageRepositoryProvider);
    Future<void>.microtask(refresh);
    return const PackageManagementState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final packages = await _repository.getPackages();
      state = state.copyWith(
        packages: packages,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
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
      List<PackageEntity> refreshed;
      try {
        refreshed = await _repository.getPackages();
      } catch (_) {
        refreshed = [
          created,
          ...state.packages.where((item) => item.id != created.id),
        ];
      }
      state = state.copyWith(
        packages: refreshed,
        isCreating: false,
        isLoading: false,
        clearError: true,
      );
      return created;
    } catch (error) {
      state = state.copyWith(isCreating: false);
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
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
      rethrow;
    }
  }

  Future<PackageEntity> setPackageActiveStatus({
    required String id,
    required bool isActive,
  }) async {
    if (state.isSaving) throw const PackageSubmissionInProgressException();
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final updated = await _repository.setPackageActiveStatus(
        id: id,
        isActive: isActive,
      );
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
      state = state.copyWith(isSaving: false, errorMessage: error.toString());
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
