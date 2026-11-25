import 'package:fitnep/features/admin/domain/entities/package_entity.dart';
import 'package:fitnep/features/admin/domain/repositories/package_repository.dart';
import 'package:fitnep/features/admin/presentation/controllers/package_management_controller.dart';
import 'package:fitnep/features/purchases/presentation/controllers/membership_controller.dart';
import 'package:flutter_test/flutter_test.dart';

final emptyPackageCatalogOverride = packageRepositoryProvider.overrideWithValue(
  _Catalog(),
);
final emptyMembershipOverride = membershipControllerProvider.overrideWith(
  _Membership.new,
);

class _Catalog extends Fake implements PackageRepository {
  @override
  Future<List<PackageEntity>> getActivePackages() async => [];
}

class _Membership extends MembershipController {
  @override
  MembershipState build() => const MembershipState();
}
