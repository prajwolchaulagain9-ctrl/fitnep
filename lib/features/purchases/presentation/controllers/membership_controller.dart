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
  final String? errorMessage;

  const MembershipState({
    this.purchase,
    this.isLoading = false,
    this.isPurchasing = false,
    this.errorMessage,
  });

  MembershipState copyWith({
    PackagePurchaseEntity? purchase,
    bool? isLoading,
    bool? isPurchasing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MembershipState(
      purchase: purchase ?? this.purchase,
      isLoading: isLoading ?? this.isLoading,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class MembershipController extends Notifier<MembershipState> {
  late PackagePurchaseRepository _repository;
  String? _pendingPackageId;
  String? _pendingRequestId;

  @override
  MembershipState build() {
    _repository = ref.watch(packagePurchaseRepositoryProvider);
    Future<void>.microtask(refresh);
    return const MembershipState(isLoading: true);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final purchase = await _repository.getCurrentPurchase();
      state = MembershipState(purchase: purchase);
    } catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  Future<PackagePurchaseEntity> purchasePackage(String packageId) async {
    if (state.isPurchasing) throw const PurchaseInProgressException();
    state = state.copyWith(isPurchasing: true, clearError: true);
    if (_pendingPackageId != packageId || _pendingRequestId == null) {
      _pendingPackageId = packageId;
      _pendingRequestId = 'purchase-${DateTime.now().microsecondsSinceEpoch}';
    }
    try {
      final purchase = await _repository.purchasePackage(
        packageId: packageId,
        requestId: _pendingRequestId!,
      );
      _pendingPackageId = null;
      _pendingRequestId = null;
      state = MembershipState(purchase: purchase);
      return purchase;
    } catch (error) {
      state = state.copyWith(
        isPurchasing: false,
        errorMessage: error.toString(),
      );
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
