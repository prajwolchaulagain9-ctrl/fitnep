import 'client_entity.dart';
import 'audit_log_entity.dart';
import 'admin_repository.dart';
import 'admin_datasource.dart';

class AdminRepositoryImpl implements AdminRepository {
  final AdminDatasource _datasource;
  AdminRepositoryImpl(this._datasource);

  @override
  Future<List<ClientEntity>> getAllClients() => _datasource.getAllClients();

  @override
  Future<ClientEntity> getClientById(String id) =>
      _datasource.getClientById(id);

  @override
  Future<List<ClientEntity>> searchClients(String query) =>
      _datasource.searchClients(query);

  @override
  Future<void> deactivateClient(
    String clientId,
    String reason,
    String adminId,
    String adminName,
  ) => _datasource.deactivateClient(clientId, reason, adminId, adminName);

  @override
  Future<void> reactivateClient(
    String clientId,
    String reason,
    String adminId,
    String adminName,
  ) => _datasource.reactivateClient(clientId, reason, adminId, adminName);

  @override
  Future<List<AuditLogEntity>> getAllAuditLogs() =>
      _datasource.getAllAuditLogs();

  @override
  Future<List<AuditLogEntity>> getAuditLogsForClient(String clientId) =>
      _datasource.getAuditLogsForClient(clientId);
}
