import '../entities/package_entity.dart';
import '../entities/package_history_entity.dart';

abstract class PackageRepository {
  /// Returns all packages (active + inactive) for admin management.
  Future<List<PackageEntity>> getPackages();

  /// Returns only active packages for customer-facing screens.
  Future<List<PackageEntity>> getActivePackages();

  Future<List<PackageHistoryEntity>> getPackageHistory();

  Future<PackageEntity> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  });

  Future<PackageEntity> updatePackage({
    required String id,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  });

  Future<PackageEntity> setPackageActiveStatus({
    required String id,
    required bool isActive,
  });
}
