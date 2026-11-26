import '../entities/client_intake.dart';

abstract class ClientIntakeRepository {
  Future<ClientIntake> getAssignedClientIntake(String clientId);

  Future<ClientIntake> updateReview({
    required String clientId,
    required ClientIntakeReviewAction action,
    String? note,
    int? expectedVersion,
    int? expectedReviewRevision,
  });
}
