import 'client_entity.dart';
import 'audit_log_entity.dart';

abstract class AdminRepository {
  Future<List<ClientEntity>> getAllClients();
  Future<ClientEntity> getClientById(String id);
  Future<List<ClientEntity>> searchClients(String query);
  Future<void> deactivateClient(
    String clientId,
    String reason,
    String adminId,
    String adminName,
  );
  Future<void> reactivateClient(
    String clientId,
    String reason,
    String adminId,
    String adminName,
  );
  Future<List<AuditLogEntity>> getAllAuditLogs();
  Future<List<AuditLogEntity>> getAuditLogsForClient(String clientId);
}
