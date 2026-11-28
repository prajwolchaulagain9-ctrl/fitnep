import 'client_entity.dart';
import 'admin_repository.dart';

class GetAllClientsUseCase {
  final AdminRepository _repository;
  GetAllClientsUseCase(this._repository);

  Future<List<ClientEntity>> call() => _repository.getAllClients();
}
