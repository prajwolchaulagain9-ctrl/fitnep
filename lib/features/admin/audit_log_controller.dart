import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/audit_log_entity.dart';
import 'data/get_audit_logs_usecase.dart';
import 'client_list_controller.dart';

final auditLogControllerProvider =
    FutureProvider.autoDispose<List<AuditLogEntity>>(
      (ref) => GetAuditLogsUseCase(ref.watch(adminRepositoryProvider))(),
      retry: (retryCount, error) => null,
    );
