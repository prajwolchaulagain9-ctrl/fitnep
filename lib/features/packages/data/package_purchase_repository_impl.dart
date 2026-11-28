import 'package_purchase_entity.dart';
import 'package_purchase_repository.dart';
import 'package_purchase_remote_datasource.dart';

class PackagePurchaseRepositoryImpl implements PackagePurchaseRepository {
  final PackagePurchaseRemoteDatasource _remoteDatasource;

  const PackagePurchaseRepositoryImpl(this._remoteDatasource);

  @override
  Future<PackagePurchaseEntity?> getCurrentPurchase() {
    return _remoteDatasource.getCurrentPurchase();
  }

  @override
  Future<PackagePurchaseEntity> purchasePackage({
    required String packageId,
    required String requestId,
  }) {
    return _remoteDatasource.purchasePackage(
      packageId: packageId,
      requestId: requestId,
    );
  }
}
