import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/authorization_refresh.dart';
import '../../shared/api_client_provider.dart';
import 'data/client_intake_remote_datasource.dart';
import 'data/client_intake_repository_impl.dart';
import 'data/intake_workspace_repository.dart';
import 'data/client_intake.dart';
import 'data/client_intake_model.dart';
import 'data/client_intake_repository.dart';

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
      final Response<Map<String, dynamic>> response;
      try {
        response = await ref
            .watch(apiClientProvider)
            .dio
            .get<Map<String, dynamic>>('intakes/me');
      } on DioException catch (error) {
        throw intakeWorkspaceError(error);
      }
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
