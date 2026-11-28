import 'package:fitnep/features/admin/data/package_entity.dart';
import 'package:fitnep/features/admin/data/package_repository.dart';
import 'package:fitnep/features/admin/package_management_controller.dart';
import 'package:fitnep/features/packages/membership_controller.dart';
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
