import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../notifications/presentation/controllers/notification_controller.dart';
import '../../data/datasources/package_purchase_remote_datasource.dart';
import '../../data/repositories/package_purchase_repository_impl.dart';
import '../../domain/entities/package_purchase_entity.dart';
import '../../domain/repositories/package_purchase_repository.dart';

final packagePurchaseRemoteDatasourceProvider =
    Provider<PackagePurchaseRemoteDatasource>((ref) {
      final ApiClient apiClient = ref.watch(apiClientProvider);
      return PackagePurchaseRemoteDatasourceImpl(apiClient);
    });

final packagePurchaseRepositoryProvider = Provider<PackagePurchaseRepository>((
  ref,
) {
  return PackagePurchaseRepositoryImpl(
    ref.watch(packagePurchaseRemoteDatasourceProvider),
  );
});

class MembershipState {
  final PackagePurchaseEntity? purchase;
  final bool isLoading;
  final bool isPurchasing;
  final String? purchasingPackageId;
  final bool hasMembershipCheckFailed;
  final String? errorMessage;

  const MembershipState({
    this.purchase,
    this.isLoading = false,
    this.isPurchasing = false,
    this.purchasingPackageId,
    this.hasMembershipCheckFailed = false,
    this.errorMessage,
  });

  MembershipState copyWith({
    PackagePurchaseEntity? purchase,
    bool? isLoading,
    bool? isPurchasing,
    String? purchasingPackageId,
    bool? hasMembershipCheckFailed,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MembershipState(
      purchase: purchase ?? this.purchase,
      isLoading: isLoading ?? this.isLoading,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      purchasingPackageId: (isPurchasing ?? this.isPurchasing)
          ? purchasingPackageId ?? this.purchasingPackageId
          : null,
      hasMembershipCheckFailed:
          hasMembershipCheckFailed ?? this.hasMembershipCheckFailed,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class MembershipController extends Notifier<MembershipState> {
  late PackagePurchaseRepository _repository;
  String? _pendingPackageId;
  String? _pendingRequestId;
  int _generation = 0;

  @override
  MembershipState build() {
    _generation++;
    _pendingPackageId = null;
    _pendingRequestId = null;
    _repository = ref.watch(packagePurchaseRepositoryProvider);
    Future<void>.microtask(refresh);
    return const MembershipState(isLoading: true);
  }

  Future<void> refresh() async {
    if (!ref.mounted || state.isPurchasing) return;
    final generation = _generation;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final purchase = await _repository.getCurrentPurchase();
      if (!ref.mounted || generation != _generation) return;
      state = MembershipState(purchase: purchase);
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        isLoading: false,
        hasMembershipCheckFailed: true,
        errorMessage: error.toString(),
      );
    }
  }

  Future<PackagePurchaseEntity> purchasePackage(String packageId) async {
    if (state.isPurchasing) throw const PurchaseInProgressException();
    final generation = ++_generation;
    state = state.copyWith(
      isPurchasing: true,
      purchasingPackageId: packageId,
      clearError: true,
    );
    if (_pendingPackageId != packageId || _pendingRequestId == null) {
      _pendingPackageId = packageId;
      _pendingRequestId = 'purchase-${DateTime.now().microsecondsSinceEpoch}';
    }
    try {
      final purchase = await _repository.purchasePackage(
        packageId: packageId,
        requestId: _pendingRequestId!,
      );
      if (ref.mounted && generation == _generation) {
        _pendingPackageId = null;
        _pendingRequestId = null;
        state = MembershipState(purchase: purchase);
      }
      return purchase;
    } catch (error) {
      if (ref.mounted && generation == _generation) {
        state = state.copyWith(
          isPurchasing: false,
          isLoading: false,
          errorMessage: error.toString(),
        );
      }
      rethrow;
    }
  }
}

class PurchaseInProgressException implements Exception {
  const PurchaseInProgressException();

  @override
  String toString() => 'A package purchase is already in progress.';
}

final membershipControllerProvider =
    NotifierProvider<MembershipController, MembershipState>(
      MembershipController.new,
    );
