import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client_provider.dart';
import '../../data/datasources/client_intake_remote_datasource.dart';
import '../../data/repositories/client_intake_repository_impl.dart';
import '../../domain/entities/client_intake.dart';
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
    .family<ClientIntake, String>((ref, clientId) {
      return ref
          .watch(clientIntakeRepositoryProvider)
          .getAssignedClientIntake(clientId);
    });
