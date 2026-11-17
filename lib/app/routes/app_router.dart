import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/admin/presentation/pages/client_list_page.dart';
import '../../features/admin/presentation/pages/client_profile_page.dart';
import '../../features/admin/presentation/pages/audit_log_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.adminClients,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.adminClients,
        name: 'admin-clients',
        builder: (context, state) => const ClientListPage(),
        routes: [
          GoRoute(
            path: ':id',
            name: 'client-profile',
            builder: (context, state) {
              final clientId = state.pathParameters['id']!;
              return ClientProfilePage(clientId: clientId);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.auditLog,
        name: 'audit-log',
        builder: (context, state) => const AuditLogPage(),
      ),
    ],
  );
});
