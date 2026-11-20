enum PackageHistoryAction { created, updated, activated, deactivated }

extension PackageHistoryActionDisplay on PackageHistoryAction {
  String get label {
    switch (this) {
      case PackageHistoryAction.created:
        return 'Package created';
      case PackageHistoryAction.updated:
        return 'Package updated';
      case PackageHistoryAction.activated:
        return 'Package activated';
      case PackageHistoryAction.deactivated:
        return 'Package deactivated';
    }
  }
}

class PackageHistoryEntity {
  final String id;
  final String packageId;
  final String packageName;
  final String adminId;
  final String adminName;
  final PackageHistoryAction action;
  final Map<String, Object?>? previousValues;
  final Map<String, Object?> newValues;
  final DateTime changedAt;

  const PackageHistoryEntity({
    required this.id,
    required this.packageId,
    required this.packageName,
    required this.adminId,
    required this.adminName,
    required this.action,
    required this.previousValues,
    required this.newValues,
    required this.changedAt,
  });
}
