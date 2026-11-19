import '../repositories/admin_repository.dart';

class DeactivateClientUseCase {
  final AdminRepository _repository;
  DeactivateClientUseCase(this._repository);

  Future<void> call({
    required String clientId,
    required String reason,
    required String adminId,
    required String adminName,
  }) => _repository.deactivateClient(clientId, reason, adminId, adminName);
}
