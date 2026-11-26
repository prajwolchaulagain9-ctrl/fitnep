import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/authorization/authorization_refresh.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../data/datasources/client_intake_remote_datasource.dart';
import '../../data/repositories/client_intake_repository_impl.dart';
import '../../domain/entities/client_intake.dart';
import '../../data/models/client_intake_model.dart';
import '../../domain/repositories/client_intake_repository.dart';

final clientIntakeRemoteDatasourceProvider =
    Provider<ClientIntakeRemoteDatasource>((ref) {
      return ClientIntakeRemoteDatasourceImpl(ref.watch(apiClientProvider));
    });

final clientIntakeRepositoryProvider = Provider<ClientIntakeRepository>((ref) {
  return ClientIntakeRepositoryImpl(
    ref.watch(clientIntakeRemoteDatasourceProvider),
  );
});

final clientIntakeProvider = FutureProvider.autoDispose
    .family<ClientIntake, ({String clientId, String viewerId})>((ref, access) {
      ref.watch(authorizationEpochProvider);
      return ref
          .watch(clientIntakeRepositoryProvider)
          .getAssignedClientIntake(access.clientId);
    }, retry: (retryCount, error) => null);

final ownClientIntakeProvider = FutureProvider.autoDispose
    .family<ClientIntake, String>((ref, uid) async {
      ref.watch(authorizationEpochProvider);
      final response = await ref
          .watch(apiClientProvider)
          .dio
          .get<Map<String, dynamic>>('intakes/me');
      final payload = response.data?['data']?['intake'];
      if (payload is! Map) {
        throw const FormatException(
          'The saved intake form could not be displayed.',
        );
      }
      return ClientIntakeModel.fromJson(
        Map<String, dynamic>.from(payload),
        requestedClientId: uid,
      );
    }, retry: (retryCount, error) => null);
