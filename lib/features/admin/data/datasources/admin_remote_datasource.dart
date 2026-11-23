import '../../../authorization/data/authorization_repository.dart';
import '../../domain/entities/client_entity.dart';
import '../../domain/entities/audit_log_entity.dart';
import '../models/client_model.dart';
import 'admin_datasource.dart';

class AdminRemoteDatasource implements AdminDatasource {
  AdminRemoteDatasource(this.repository);
  final AuthorizationRepository repository;
  @override
  Future<List<ClientEntity>> getAllClients() async => (await repository.all(
    'admin/clients',
    'clients',
  )).map(ClientModel.fromJson).toList();
  @override
  Future<ClientEntity> getClientById(String id) async => ClientModel.fromJson(
    Map<String, dynamic>.from(
      (await repository.request(
            'admin/clients/${Uri.encodeComponent(id)}',
          ))['client']
          as Map,
    ),
  );
  @override
  Future<List<ClientEntity>> searchClients(String query) async =>
      (await getAllClients())
          .where(
            (client) => client.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
  @override
  Future<void> deactivateClient(
    String id,
    String reason,
    String adminId,
    String adminName,
  ) async {
    await repository.request(
      'admin/clients/${Uri.encodeComponent(id)}/status',
      method: 'PATCH',
      data: {'account_status': 'inactive', 'reason': reason},
    );
  }

  @override
  Future<void> reactivateClient(
    String id,
    String reason,
    String adminId,
    String adminName,
  ) async {
    await repository.request(
      'admin/clients/${Uri.encodeComponent(id)}/status',
      method: 'PATCH',
      data: {'account_status': 'active', 'reason': reason},
    );
  }

  @override
  Future<List<AuditLogEntity>> getAllAuditLogs() async =>
      (await repository.all('admin/audit-logs', 'logs')).map(_audit).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  @override
  Future<List<AuditLogEntity>> getAuditLogsForClient(String id) async =>
      (await repository.all(
        'admin/audit-logs',
        'logs',
        query: {'record_id': id},
      )).map(_audit).toList();
  AuditLogEntity _audit(Map<String, dynamic> data) {
    final result = data['result'] as String?;
    final action = data['action'] as String? ?? '';
    return AuditLogEntity(
      id: data['id'] as String,
      adminId: data['user_id'] as String? ?? '',
      adminName:
          '${data['user_id'] ?? 'Unauthenticated'} (${data['current_role'] ?? 'unassigned'})',
      clientId: data['record_id'] as String? ?? '',
      clientName:
          data['record_id'] as String? ?? data['resource'] as String? ?? '',
      actionType: result == 'DENIED'
          ? AuditActionType.authorizationDenied
          : switch (action) {
              'manage_user_roles' => AuditActionType.userRoleChanged,
              'manage_client_assignments' =>
                AuditActionType.clientAssignmentChanged,
              _ => AuditActionType.accountStatusChanged,
            },
      reason: data['reason'] as String?,
      details:
          '${result ?? ''}: $action • ${data['resource'] ?? ''}'
          '${data['previous_role'] != null ? ' • ${data['previous_role']} → ${data['new_role']}' : ''}',
      timestamp: DateTime.parse(data['timestamp'] as String),
    );
  }
}
