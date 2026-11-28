enum AssignedClientPlanStatus {
  noPlan('no_plan', 'No plan yet'),
  draft('draft', 'Draft'),
  submitted('submitted', 'Submitted'),
  returned('returned', 'Returned'),
  approved('approved', 'Approved'),
  published('published', 'Published'),
  unavailable('unavailable', 'Status unavailable');

  const AssignedClientPlanStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static AssignedClientPlanStatus fromApi(Object? value) => values.firstWhere(
    (status) => status.apiValue == value,
    orElse: () => unavailable,
  );
}

class AssignedClient {
  AssignedClient.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      fullName = json['full_name'] as String,
      email = json['email'] as String,
      planStatus = AssignedClientPlanStatus.fromApi(json['plan_status']),
      packageStatus = switch (json['package_status']) {
        'active' => 'Active',
        'pending' => 'Pending',
        'scheduled' => 'Scheduled',
        'expired' => 'Expired',
        'inactive' => 'Inactive',
        'none' => 'No package',
        _ => 'Status unavailable',
      },
      intakeStatus = switch (json['intake_status']) {
        'submitted' => 'Submitted',
        'reviewed' => 'Reviewed',
        'information_requested' => 'Pending information',
        _ => null,
      },
      lastActivityAt = DateTime.tryParse(
        json['last_activity_at'] as String? ?? '',
      );

  final String id;
  final String fullName;
  final String email;
  final AssignedClientPlanStatus planStatus;
  final String packageStatus;
  final String? intakeStatus;
  final DateTime? lastActivityAt;
}

typedef AssignedClientPage = ({
  List<AssignedClient> clients,
  String? nextCursor,
});
