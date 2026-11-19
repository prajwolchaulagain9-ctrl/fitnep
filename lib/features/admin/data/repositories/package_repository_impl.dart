import '../../domain/entities/package_entity.dart';
import '../../domain/repositories/package_repository.dart';
import '../datasources/package_remote_datasource.dart';

class PackageRepositoryImpl implements PackageRepository {
  final PackageRemoteDatasource _remoteDatasource;

  const PackageRepositoryImpl(this._remoteDatasource);

  @override
  Future<List<PackageEntity>> getPackages() async {
    final packages = await _remoteDatasource.getPackages();
    return List<PackageEntity>.unmodifiable(packages);
  }

  @override
  Future<PackageEntity> createPackage({
    required String requestId,
    required String name,
    required int durationMonths,
    required double price,
    required String featureDescription,
  }) {
    return _remoteDatasource.createPackage(
      requestId: requestId,
      name: name,
      durationMonths: durationMonths,
      price: price,
      featureDescription: featureDescription,
    );
  }
}
