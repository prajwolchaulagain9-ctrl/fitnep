import '../../domain/entities/client_intake.dart';
import '../../domain/repositories/client_intake_repository.dart';
import '../datasources/client_intake_remote_datasource.dart';

class ClientIntakeRepositoryImpl implements ClientIntakeRepository {
  const ClientIntakeRepositoryImpl(this._remote);

  final ClientIntakeRemoteDatasource _remote;

  @override
  Future<ClientIntake> getAssignedClientIntake(String clientId) =>
      _remote.getAssignedClientIntake(clientId);

  @override
  Future<ClientIntake> updateReview({
    required String clientId,
    required ClientIntakeReviewAction action,
    String? note,
  }) => _remote.updateReview(clientId: clientId, action: action, note: note);
}
