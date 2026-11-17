import '../../domain/entities/client_entity.dart';

class ClientModel extends ClientEntity {
  const ClientModel({
    required super.id,
    required super.name,
    required super.email,
    required super.phone,
    required super.gender,
    required super.dateOfBirth,
    required super.address,
    required super.packageId,
    required super.packageName,
    required super.status,
    required super.assignedDietitianId,
    required super.assignedDietitianName,
    required super.joinDate,
    super.deactivatedAt,
    super.deactivationReason,
    required super.totalAmountPaid,
    required super.outstandingAmount,
    super.lastPaymentDate,
    required super.paymentHistory,
    required super.packageHistory,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      phone: json['phone'] as String,
      gender: Gender.values.firstWhere(
        (g) => g.name == json['gender'],
        orElse: () => Gender.other,
      ),
      dateOfBirth: DateTime.parse(json['dateOfBirth'] as String),
      address: json['address'] as String,
      packageId: json['packageId'] as String,
      packageName: json['packageName'] as String,
      status: ClientStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ClientStatus.active,
      ),
      assignedDietitianId: json['assignedDietitianId'] as String,
      assignedDietitianName: json['assignedDietitianName'] as String,
      joinDate: DateTime.parse(json['joinDate'] as String),
      deactivatedAt: json['deactivatedAt'] != null
          ? DateTime.parse(json['deactivatedAt'] as String)
          : null,
      deactivationReason: json['deactivationReason'] as String?,
      totalAmountPaid: (json['totalAmountPaid'] as num).toDouble(),
      outstandingAmount: (json['outstandingAmount'] as num).toDouble(),
      lastPaymentDate: json['lastPaymentDate'] != null
          ? DateTime.parse(json['lastPaymentDate'] as String)
          : null,
      paymentHistory: (json['paymentHistory'] as List<dynamic>)
          .map((e) => _paymentFromJson(e as Map<String, dynamic>))
          .toList(),
      packageHistory: (json['packageHistory'] as List<dynamic>)
          .map((e) => _packageHistoryFromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'gender': gender.name,
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'address': address,
      'packageId': packageId,
      'packageName': packageName,
      'status': status.name,
      'assignedDietitianId': assignedDietitianId,
      'assignedDietitianName': assignedDietitianName,
      'joinDate': joinDate.toIso8601String(),
      'deactivatedAt': deactivatedAt?.toIso8601String(),
      'deactivationReason': deactivationReason,
      'totalAmountPaid': totalAmountPaid,
      'outstandingAmount': outstandingAmount,
      'lastPaymentDate': lastPaymentDate?.toIso8601String(),
      'paymentHistory':
          paymentHistory.map((e) => _paymentToJson(e)).toList(),
      'packageHistory':
          packageHistory.map((e) => _packageHistoryToJson(e)).toList(),
    };
  }

  static PaymentHistoryEntry _paymentFromJson(Map<String, dynamic> json) {
    return PaymentHistoryEntry(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      amount: (json['amount'] as num).toDouble(),
      status: PaymentStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => PaymentStatus.pending,
      ),
      description: json['description'] as String,
    );
  }

  static Map<String, dynamic> _paymentToJson(PaymentHistoryEntry e) => {
        'id': e.id,
        'date': e.date.toIso8601String(),
        'amount': e.amount,
        'status': e.status.name,
        'description': e.description,
      };

  static PackageHistoryEntry _packageHistoryFromJson(
      Map<String, dynamic> json) {
    return PackageHistoryEntry(
      packageId: json['packageId'] as String,
      packageName: json['packageName'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
    );
  }

  static Map<String, dynamic> _packageHistoryToJson(PackageHistoryEntry e) => {
        'packageId': e.packageId,
        'packageName': e.packageName,
        'startDate': e.startDate.toIso8601String(),
        'endDate': e.endDate?.toIso8601String(),
      };
}
