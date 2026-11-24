import '../entities/client_intake.dart';

abstract class ClientIntakeRepository {
  Future<ClientIntake> getAssignedClientIntake(String clientId);
}
