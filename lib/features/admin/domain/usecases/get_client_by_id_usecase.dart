import '../entities/client_entity.dart';
import '../repositories/admin_repository.dart';

class GetClientByIdUseCase {
  final AdminRepository _repository;
  GetClientByIdUseCase(this._repository);

  Future<ClientEntity> call(String id) => _repository.getClientById(id);
}
