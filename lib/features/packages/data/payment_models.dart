import 'package_models.dart';

enum PaymentStatus {
  pending('Pending'),
  verified('Verified'),
  rejected('Rejected');

  const PaymentStatus(this.label);
  final String label;
}

class PackageCheckout {
  const PackageCheckout({
    required this.membershipId,
    required this.package,
    required this.amountNpr,
    required this.reference,
    required this.qrPayload,
    this.paymentId,
    this.paymentStatus,
  });

  final String membershipId;
  final PackageOption package;
  final num amountNpr;
  final String reference;
  final String qrPayload;
  final String? paymentId;
  final PaymentStatus? paymentStatus;

  factory PackageCheckout.fromJson(Map<String, dynamic> json) =>
      PackageCheckout(
        membershipId: json['membership_id'] as String,
        package: PackageOption.fromJson(
          json['package'] as Map<String, dynamic>,
        ),
        amountNpr: json['amount_npr'] as num,
        reference: json['reference'] as String,
        qrPayload: json['qr_payload'] as String,
        paymentId: json['payment_id'] as String?,
        paymentStatus: json['payment_status'] == null
            ? null
            : PaymentStatus.values.byName(json['payment_status'] as String),
      );
}

class PackagePayment {
  const PackagePayment({
    required this.id,
    required this.membershipId,
    required this.clientName,
    required this.package,
    required this.amountNpr,
    required this.reference,
    required this.qrPayload,
    required this.status,
    required this.createdAt,
    this.revision,
    this.reviewedAt,
    this.reviewedByName,
    this.rejectionReason,
  });

  final String id;
  final String membershipId;
  final String clientName;
  final PackageOption package;
  final num amountNpr;
  final String reference;
  final String qrPayload;
  final PaymentStatus status;
  final DateTime createdAt;
  final int? revision;
  final DateTime? reviewedAt;
  final String? reviewedByName;
  final String? rejectionReason;

  factory PackagePayment.fromJson(Map<String, dynamic> json) => PackagePayment(
    id: json['id'] as String,
    membershipId: json['membership_id'] as String,
    clientName: json['client_name'] as String,
    package: PackageOption.fromJson(json['package'] as Map<String, dynamic>),
    amountNpr: json['amount_npr'] as num,
    reference: json['reference'] as String,
    qrPayload: json['qr_payload'] as String,
    status: PaymentStatus.values.byName(json['status'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    revision: json['revision'] as int?,
    reviewedAt: json['reviewed_at'] == null
        ? null
        : DateTime.parse(json['reviewed_at'] as String),
    reviewedByName: json['reviewed_by_name'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
  );
}

class PaymentAdjustment {
  const PaymentAdjustment({
    required this.amountDeltaNpr,
    required this.reason,
    required this.createdAt,
    this.createdByName,
  });

  final num amountDeltaNpr;
  final String reason;
  final DateTime createdAt;
  final String? createdByName;

  factory PaymentAdjustment.fromJson(Map<String, dynamic> json) =>
      PaymentAdjustment(
        amountDeltaNpr: json['amount_delta_npr'] as num,
        reason: json['reason'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        createdByName: json['created_by_name'] as String?,
      );
}

typedef PaymentDetails = ({
  PackagePayment payment,
  List<PaymentAdjustment> adjustments,
});
