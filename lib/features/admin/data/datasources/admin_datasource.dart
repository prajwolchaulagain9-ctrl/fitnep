import '../../domain/entities/client_entity.dart';
import '../../domain/entities/audit_log_entity.dart';

abstract interface class AdminDatasource {
  Future<List<ClientEntity>> getAllClients();
  Future<ClientEntity> getClientById(String id);
  Future<List<ClientEntity>> searchClients(String query);
  Future<void> deactivateClient(
    String id,
    String reason,
    String adminId,
    String adminName,
  );
  Future<void> reactivateClient(
    String id,
    String reason,
    String adminId,
    String adminName,
  );
  Future<List<AuditLogEntity>> getAllAuditLogs();
  Future<List<AuditLogEntity>> getAuditLogsForClient(String id);
}
