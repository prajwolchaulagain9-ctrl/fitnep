import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/audit_log_entity.dart';
import '../../domain/usecases/get_audit_logs_usecase.dart';
import 'client_list_controller.dart';

final auditLogControllerProvider =
    FutureProvider.autoDispose<List<AuditLogEntity>>(
      (ref) => GetAuditLogsUseCase(ref.watch(adminRepositoryProvider))(),
      retry: (retryCount, error) => null,
    );
