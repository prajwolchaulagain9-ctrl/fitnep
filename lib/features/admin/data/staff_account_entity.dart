enum StaffRole {
  staff('Staff'),
  dietitian('Dietitian'),
  admin('Admin');

  const StaffRole(this.label);
  final String label;
}

class StaffAccount {
  const StaffAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
  });

  final String uid;
  final String? name;
  final String? email;
  final StaffRole role;
  final bool isActive;

  String get displayName => name ?? email ?? uid;
}

enum StaffAccountAction {
  created('Account created'),
  updated('Account edited'),
  roleChanged('Role changed'),
  deactivated('Account deactivated'),
  reactivated('Account reactivated');

  const StaffAccountAction(this.label);
  final String label;
}

class StaffAccountHistoryEntry {
  const StaffAccountHistoryEntry({
    required this.action,
    required this.actor,
    required this.before,
    required this.after,
    required this.completedAt,
  });

  final StaffAccountAction action;
  final String actor;
  final StaffAccount? before;
  final StaffAccount after;
  final DateTime completedAt;
}

typedef StaffPage<T> = ({List<T> items, String? nextCursor});
