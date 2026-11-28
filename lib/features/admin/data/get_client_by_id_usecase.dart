import 'client_entity.dart';
import 'admin_repository.dart';

class GetClientByIdUseCase {
  final AdminRepository _repository;
  GetClientByIdUseCase(this._repository);

  Future<ClientEntity> call(String id) => _repository.getClientById(id);
}
