import '../../domain/entities/client_entity.dart';
import '../../domain/entities/audit_log_entity.dart';
import '../models/audit_log_model.dart';
import 'admin_datasource.dart';

/// In-memory datasource that simulates async API behaviour.
/// Replace this with a real network datasource (Dio) when the backend is ready.
class AdminLocalDatasource implements AdminDatasource {
  // Mutable in-memory store
  final List<ClientEntity> _clients = _buildInitialClients();
  final List<AuditLogEntity> _auditLogs = [];

  // ── Clients ──────────────────────────────────────────────────────────────

  @override
  Future<List<ClientEntity>> getAllClients() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return List.unmodifiable(_clients);
  }

  @override
  Future<ClientEntity> getClientById(String id) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _clients.firstWhere(
      (c) => c.id == id,
      orElse: () => throw Exception('Client not found: $id'),
    );
  }

  @override
  Future<List<ClientEntity>> searchClients(String query) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return List.unmodifiable(_clients);
    return _clients.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  // ── Deactivation / Reactivation ───────────────────────────────────────

  @override
  Future<void> deactivateClient(
    String clientId,
    String reason,
    String adminId,
    String adminName,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final idx = _clients.indexWhere((c) => c.id == clientId);
    if (idx == -1) throw Exception('Client not found: $clientId');
    final client = _clients[idx];
    _clients[idx] = client.copyWith(
      status: ClientStatus.inactive,
      deactivatedAt: DateTime.now(),
      deactivationReason: reason,
    );
    _logAction(
      adminId: adminId,
      adminName: adminName,
      clientId: clientId,
      clientName: client.name,
      actionType: AuditActionType.clientDeactivated,
      reason: reason,
    );
  }

  @override
  Future<void> reactivateClient(
    String clientId,
    String reason,
    String adminId,
    String adminName,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final idx = _clients.indexWhere((c) => c.id == clientId);
    if (idx == -1) throw Exception('Client not found: $clientId');
    final client = _clients[idx];
    _clients[idx] = client.copyWith(
      status: ClientStatus.active,
      deactivationReason: null,
    );
    _logAction(
      adminId: adminId,
      adminName: adminName,
      clientId: clientId,
      clientName: client.name,
      actionType: AuditActionType.clientReactivated,
      reason: reason,
    );
  }

  // ── Audit Logs ───────────────────────────────────────────────────────────

  @override
  Future<List<AuditLogEntity>> getAllAuditLogs() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return List.unmodifiable(
      _auditLogs..sort((a, b) => b.timestamp.compareTo(a.timestamp)),
    );
  }

  @override
  Future<List<AuditLogEntity>> getAuditLogsForClient(String clientId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _auditLogs.where((l) => l.clientId == clientId).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _logAction({
    required String adminId,
    required String adminName,
    required String clientId,
    required String clientName,
    required AuditActionType actionType,
    String? reason,
    String? details,
  }) {
    _auditLogs.add(
      AuditLogModel(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        adminId: adminId,
        adminName: adminName,
        clientId: clientId,
        clientName: clientName,
        actionType: actionType,
        reason: reason,
        details: details,
        timestamp: DateTime.now(),
      ),
    );
  }

  // ── Seed data ─────────────────────────────────────────────────────────────

  static List<ClientEntity> _buildInitialClients() {
    final dietitians = [
      ('d1', 'Dr. Sarah Ali'),
      ('d2', 'Dr. Rajan Thapa'),
      ('d3', 'Dr. Priya Sharma'),
      ('d4', 'Dr. Milan Karki'),
    ];

    final packages = [
      ('pkg_basic', 'Basic'),
      ('pkg_standard', 'Standard'),
      ('pkg_premium', 'Premium'),
      ('pkg_elite', 'Elite'),
    ];

    final clientData = [
      (
        'Anjali Shrestha',
        'anjali.shrestha@email.com',
        '9841000001',
        Gender.female,
        '1995-03-14',
        'Kathmandu-6, Lazimpat',
        0,
        2,
        ClientStatus.active,
      ),
      (
        'Bikash Tamang',
        'bikash.tamang@email.com',
        '9841000002',
        Gender.male,
        '1990-07-22',
        'Lalitpur-3, Jawalakhel',
        1,
        0,
        ClientStatus.active,
      ),
      (
        'Deepa Gurung',
        'deepa.gurung@email.com',
        '9841000003',
        Gender.female,
        '1988-11-05',
        'Bhaktapur-5, Suryabinayak',
        2,
        1,
        ClientStatus.active,
      ),
      (
        'Ramesh KC',
        'ramesh.kc@email.com',
        '9841000004',
        Gender.male,
        '1992-01-30',
        'Kathmandu-32, Baneshwor',
        3,
        3,
        ClientStatus.active,
      ),
      (
        'Sunita Rai',
        'sunita.rai@email.com',
        '9841000005',
        Gender.female,
        '1998-06-18',
        'Lalitpur-15, Patan',
        0,
        0,
        ClientStatus.inactive,
      ),
      (
        'Nabin Poudel',
        'nabin.poudel@email.com',
        '9841000006',
        Gender.male,
        '1985-09-12',
        'Kathmandu-9, Balaju',
        1,
        2,
        ClientStatus.active,
      ),
      (
        'Kamala Thapa',
        'kamala.thapa@email.com',
        '9841000007',
        Gender.female,
        '2000-02-28',
        'Bhaktapur-6, Changunarayan',
        2,
        3,
        ClientStatus.active,
      ),
      (
        'Suresh Magar',
        'suresh.magar@email.com',
        '9841000008',
        Gender.male,
        '1993-12-15',
        'Kathmandu-16, Koteshwor',
        3,
        1,
        ClientStatus.inactive,
      ),
      (
        'Puja Limbu',
        'puja.limbu@email.com',
        '9841000009',
        Gender.female,
        '1997-04-03',
        'Lalitpur-20, Kumaripati',
        0,
        1,
        ClientStatus.active,
      ),
      (
        'Ashish Basnet',
        'ashish.basnet@email.com',
        '9841000010',
        Gender.male,
        '1989-08-20',
        'Kathmandu-4, Maharajgunj',
        1,
        3,
        ClientStatus.active,
      ),
      (
        'Rita Pandey',
        'rita.pandey@email.com',
        '9841000011',
        Gender.female,
        '1994-05-11',
        'Bhaktapur-1, Katunje',
        2,
        0,
        ClientStatus.active,
      ),
      (
        'Dinesh Lama',
        'dinesh.lama@email.com',
        '9841000012',
        Gender.male,
        '1987-10-07',
        'Kathmandu-27, Naxal',
        3,
        2,
        ClientStatus.active,
      ),
      (
        'Srijana Pokhrel',
        'srijana.pokhrel@email.com',
        '9841000013',
        Gender.female,
        '1999-01-25',
        'Lalitpur-8, Ekantakuna',
        0,
        3,
        ClientStatus.inactive,
      ),
      (
        'Prakash Adhikari',
        'prakash.adhikari@email.com',
        '9841000014',
        Gender.male,
        '1991-07-14',
        'Kathmandu-11, Chabahil',
        1,
        1,
        ClientStatus.active,
      ),
      (
        'Manisha Karmacharya',
        'manisha.kc@email.com',
        '9841000015',
        Gender.female,
        '1996-03-08',
        'Bhaktapur-9, Dattatreya',
        2,
        2,
        ClientStatus.active,
      ),
      (
        'Gaurav Silwal',
        'gaurav.silwal@email.com',
        '9841000016',
        Gender.male,
        '1983-11-30',
        'Kathmandu-19, Kalimati',
        3,
        0,
        ClientStatus.active,
      ),
      (
        'Binita Ghimire',
        'binita.ghimire@email.com',
        '9841000017',
        Gender.female,
        '2001-06-22',
        'Lalitpur-25, Sanepa',
        0,
        2,
        ClientStatus.active,
      ),
      (
        'Santosh Dhakal',
        'santosh.dhakal@email.com',
        '9841000018',
        Gender.male,
        '1986-04-17',
        'Kathmandu-14, Bagbazar',
        1,
        1,
        ClientStatus.inactive,
      ),
      (
        'Kabita Maharjan',
        'kabita.maharjan@email.com',
        '9841000019',
        Gender.female,
        '1993-09-29',
        'Bhaktapur-11, Lokanthali',
        2,
        3,
        ClientStatus.active,
      ),
      (
        'Raju Shrestha',
        'raju.shrestha@email.com',
        '9841000020',
        Gender.male,
        '1979-12-04',
        'Kathmandu-2, Durbarmarg',
        3,
        0,
        ClientStatus.active,
      ),
    ];

    return clientData.asMap().entries.map((entry) {
      final i = entry.key;
      final d = entry.value;
      final clientId = 'client_${(i + 1).toString().padLeft(3, '0')}';
      final pkgIndex = d.$7;
      final dietIndex = d.$8;
      final pkg = packages[pkgIndex];
      final diet = dietitians[dietIndex];
      final joinDate = DateTime.now().subtract(
        Duration(days: 30 * (i + 2) + i * 7),
      );
      final isInactive = d.$9 == ClientStatus.inactive;

      final payments = _buildPayments(clientId, joinDate, pkgIndex);
      final totalPaid = payments
          .where((p) => p.status == PaymentStatus.paid)
          .fold<double>(0, (sum, p) => sum + p.amount);
      final outstanding = payments
          .where(
            (p) =>
                p.status == PaymentStatus.pending ||
                p.status == PaymentStatus.overdue,
          )
          .fold<double>(0, (sum, p) => sum + p.amount);
      final lastPaid = payments
          .where((p) => p.status == PaymentStatus.paid)
          .map((p) => p.date)
          .fold<DateTime?>(
            null,
            (latest, d) => latest == null || d.isAfter(latest) ? d : latest,
          );

      return ClientEntity(
        id: clientId,
        name: d.$1,
        email: d.$2,
        phone: d.$3,
        gender: d.$4,
        dateOfBirth: DateTime.parse(d.$5),
        address: d.$6,
        packageId: pkg.$1,
        packageName: pkg.$2,
        status: d.$9,
        assignedDietitianId: diet.$1,
        assignedDietitianName: diet.$2,
        joinDate: joinDate,
        deactivatedAt: isInactive
            ? joinDate.add(const Duration(days: 45))
            : null,
        deactivationReason: isInactive
            ? 'Non-payment of dues for 2+ months'
            : null,
        totalAmountPaid: totalPaid,
        outstandingAmount: outstanding,
        lastPaymentDate: lastPaid,
        paymentHistory: payments,
        packageHistory: _buildPackageHistory(
          joinDate,
          pkg.$1,
          pkg.$2,
          pkgIndex,
        ),
      );
    }).toList();
  }

  static final _packagePrices = [2500.0, 4500.0, 7500.0, 12000.0];

  static List<PaymentHistoryEntry> _buildPayments(
    String clientId,
    DateTime joinDate,
    int pkgIndex,
  ) {
    final price = _packagePrices[pkgIndex];
    final months = 5 + pkgIndex;
    return List.generate(months, (i) {
      final date = joinDate.add(Duration(days: 30 * i));
      PaymentStatus status;
      if (i < months - 2) {
        status = PaymentStatus.paid;
      } else if (i == months - 2) {
        status = PaymentStatus.pending;
      } else {
        status = i % 3 == 0 ? PaymentStatus.overdue : PaymentStatus.paid;
      }
      return PaymentHistoryEntry(
        id: 'pay_${clientId}_$i',
        date: date,
        amount: price,
        status: status,
        description: 'Monthly subscription – ${_monthLabel(date)}',
      );
    });
  }

  static List<PackageHistoryEntry> _buildPackageHistory(
    DateTime joinDate,
    String pkgId,
    String pkgName,
    int pkgIndex,
  ) {
    final history = <PackageHistoryEntry>[];
    if (pkgIndex > 0) {
      final prevPkg = [
        'Basic',
        'Standard',
        'Premium',
      ][pkgIndex - 1 < 3 ? pkgIndex - 1 : 2];
      final prevId = [
        'pkg_basic',
        'pkg_standard',
        'pkg_premium',
      ][pkgIndex - 1 < 3 ? pkgIndex - 1 : 2];
      history.add(
        PackageHistoryEntry(
          packageId: prevId,
          packageName: prevPkg,
          startDate: joinDate,
          endDate: joinDate.add(const Duration(days: 90)),
        ),
      );
    }
    history.add(
      PackageHistoryEntry(
        packageId: pkgId,
        packageName: pkgName,
        startDate: pkgIndex > 0
            ? joinDate.add(const Duration(days: 90))
            : joinDate,
        endDate: null,
      ),
    );
    return history;
  }

  static String _monthLabel(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
