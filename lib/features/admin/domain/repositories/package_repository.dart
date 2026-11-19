import '../entities/package_entity.dart';

abstract class PackageRepository {
  Future<List<PackageEntity>> getPackages();

  Future<PackageEntity> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  });
}
