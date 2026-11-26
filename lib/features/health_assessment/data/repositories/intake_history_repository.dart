import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/authorization/authorization_refresh.dart';
import '../../../../core/network/api_client_provider.dart';
import '../../domain/entities/client_intake.dart';
import '../datasources/client_intake_remote_datasource.dart';
import '../models/client_intake_model.dart';
import 'intake_workspace_repository.dart';

typedef IntakeVersionSummary = ({int version, DateTime? submittedAt});
typedef IntakeHistoryPageData = ({
  List<IntakeVersionSummary> versions,
  int? nextBefore,
});

final intakeHistoryRepositoryProvider = Provider<IntakeHistoryRepository>(
  (ref) => IntakeHistoryRepository(ref.watch(apiClientProvider).dio),
);

final intakeVersionProvider = FutureProvider.autoDispose
    .family<ClientIntake, ({String clientId, String viewerId, int version})>((
      ref,
      access,
    ) {
      ref.watch(authorizationEpochProvider);
      return ref
          .watch(intakeHistoryRepositoryProvider)
          .getVersion(access.clientId, access.version);
    }, retry: (retryCount, error) => null);

class IntakeHistoryRepository {
  const IntakeHistoryRepository(this._dio);

  final Dio _dio;

  Future<IntakeHistoryPageData> listVersions(String clientId, {int? before}) =>
      _read(
        clientId,
        before: before,
        decode: (data) {
          final rawVersions = data['versions'];
          if (data['client_id'] != clientId || rawVersions is! List) {
            throw const FormatException('Invalid intake history.');
          }
          final versions = <IntakeVersionSummary>[];
          var upperBound = before;
          for (final row in rawVersions) {
            if (row is! Map || row['version'] is! int) {
              throw const FormatException('Invalid intake version.');
            }
            final version = row['version'] as int;
            if (version < 1 || (upperBound != null && version >= upperBound)) {
              throw const FormatException('Invalid intake version order.');
            }
            final rawDate = row['submitted_at'];
            versions.add((
              version: version,
              submittedAt: rawDate is String
                  ? DateTime.tryParse(rawDate)
                  : null,
            ));
            upperBound = version;
          }
          final cursor = data['next_before'];
          if (cursor != null &&
              (versions.isEmpty || cursor != versions.last.version)) {
            throw const FormatException('Invalid intake page cursor.');
          }
          return (versions: versions, nextBefore: cursor as int?);
        },
      );

  Future<ClientIntake> getVersion(String clientId, int version) => _read(
    clientId,
    version: version,
    decode: (data) {
      final rawIntake = data['intake'];
      if (rawIntake is! Map) {
        throw const FormatException('Missing submitted intake.');
      }
      final intake = ClientIntakeModel.fromJson(
        Map<String, dynamic>.from(rawIntake),
        requestedClientId: clientId,
      );
      if (intake.version != version) {
        throw const FormatException('Mismatched intake version.');
      }
      return intake;
    },
  );

  Future<T> _read<T>(
    String clientId, {
    int? version,
    int? before,
    required T Function(Map data) decode,
  }) async {
    final path = 'clients/${Uri.encodeComponent(clientId)}/intake/versions';
    try {
      final response = await _dio.get<Object?>(
        version == null ? path : '$path/$version',
        queryParameters: {'before': ?before},
      );
      final payload = response.data;
      if (payload is! Map || payload['data'] is! Map) {
        throw const FormatException('Missing intake history.');
      }
      return decode(payload['data'] as Map);
    } on DioException catch (error) {
      throw intakeWorkspaceError(error);
    } on FormatException {
      throw const ClientIntakeException(
        ClientIntakeFailure.invalidData,
        'The intake history could not be displayed.',
      );
    }
  }
}
