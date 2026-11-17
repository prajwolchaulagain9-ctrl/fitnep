enum ClientStatus { active, inactive }

enum Gender { male, female, other }

class ClientEntity {
  final String id;
  final String name;
  final String email;
  final String phone;
  final Gender gender;
  final DateTime dateOfBirth;
  final String address;
  final String packageId;
  final String packageName;
  final ClientStatus status;
  final String assignedDietitianId;
  final String assignedDietitianName;
  final DateTime joinDate;
  final DateTime? deactivatedAt;
  final String? deactivationReason;
  final double totalAmountPaid;
  final double outstandingAmount;
  final DateTime? lastPaymentDate;
  final List<PaymentHistoryEntry> paymentHistory;
  final List<PackageHistoryEntry> packageHistory;

  const ClientEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.gender,
    required this.dateOfBirth,
    required this.address,
    required this.packageId,
    required this.packageName,
    required this.status,
    required this.assignedDietitianId,
    required this.assignedDietitianName,
    required this.joinDate,
    this.deactivatedAt,
    this.deactivationReason,
    required this.totalAmountPaid,
    required this.outstandingAmount,
    this.lastPaymentDate,
    required this.paymentHistory,
    required this.packageHistory,
  });

  ClientEntity copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    Gender? gender,
    DateTime? dateOfBirth,
    String? address,
    String? packageId,
    String? packageName,
    ClientStatus? status,
    String? assignedDietitianId,
    String? assignedDietitianName,
    DateTime? joinDate,
    DateTime? deactivatedAt,
    String? deactivationReason,
    double? totalAmountPaid,
    double? outstandingAmount,
    DateTime? lastPaymentDate,
    List<PaymentHistoryEntry>? paymentHistory,
    List<PackageHistoryEntry>? packageHistory,
  }) {
    return ClientEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      address: address ?? this.address,
      packageId: packageId ?? this.packageId,
      packageName: packageName ?? this.packageName,
      status: status ?? this.status,
      assignedDietitianId: assignedDietitianId ?? this.assignedDietitianId,
      assignedDietitianName: assignedDietitianName ?? this.assignedDietitianName,
      joinDate: joinDate ?? this.joinDate,
      deactivatedAt: deactivatedAt ?? this.deactivatedAt,
      deactivationReason: deactivationReason ?? this.deactivationReason,
      totalAmountPaid: totalAmountPaid ?? this.totalAmountPaid,
      outstandingAmount: outstandingAmount ?? this.outstandingAmount,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
      paymentHistory: paymentHistory ?? this.paymentHistory,
      packageHistory: packageHistory ?? this.packageHistory,
    );
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  int get age {
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  bool get isActive => status == ClientStatus.active;
}

enum PaymentStatus { paid, pending, overdue }

class PaymentHistoryEntry {
  final String id;
  final DateTime date;
  final double amount;
  final PaymentStatus status;
  final String description;

  const PaymentHistoryEntry({
    required this.id,
    required this.date,
    required this.amount,
    required this.status,
    required this.description,
  });
}

class PackageHistoryEntry {
  final String packageId;
  final String packageName;
  final DateTime startDate;
  final DateTime? endDate;

  const PackageHistoryEntry({
    required this.packageId,
    required this.packageName,
    required this.startDate,
    this.endDate,
  });
}
