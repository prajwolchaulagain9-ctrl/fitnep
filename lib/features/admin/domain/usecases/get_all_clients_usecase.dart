import '../entities/client_entity.dart';
import '../repositories/admin_repository.dart';

class GetAllClientsUseCase {
  final AdminRepository _repository;
  GetAllClientsUseCase(this._repository);

  Future<List<ClientEntity>> call() => _repository.getAllClients();
}
