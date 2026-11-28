import 'audit_log_entity.dart';
import 'admin_repository.dart';

class GetAuditLogsUseCase {
  final AdminRepository _repository;
  GetAuditLogsUseCase(this._repository);

  Future<List<AuditLogEntity>> call() => _repository.getAllAuditLogs();
}

class GetAuditLogsForClientUseCase {
  final AdminRepository _repository;
  GetAuditLogsForClientUseCase(this._repository);

  Future<List<AuditLogEntity>> call(String clientId) =>
      _repository.getAuditLogsForClient(clientId);
}
