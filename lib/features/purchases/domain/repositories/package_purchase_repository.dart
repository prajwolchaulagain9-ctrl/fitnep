import '../entities/package_purchase_entity.dart';

abstract class PackagePurchaseRepository {
  Future<PackagePurchaseEntity?> getCurrentPurchase();

  Future<PackagePurchaseEntity> purchasePackage({
    required String packageId,
    required String requestId,
  });
}
