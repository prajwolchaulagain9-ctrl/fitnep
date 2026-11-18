import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/pages/client_list_page.dart';
import '../../features/admin/presentation/pages/client_profile_page.dart';
import '../../features/admin/presentation/pages/audit_log_page.dart';
import '../../features/dashboards/presentation/pages/client_home_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/notifications/domain/entities/notification_entity.dart';
import '../../features/notifications/presentation/pages/notification_destination_page.dart';
import 'app_routes.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.adminClients,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(
        path: AppRoutes.clientHome,
        name: AppRoutes.clientHomeName,
        builder: (context, state) => const ClientHomePage(),
      ),
      GoRoute(
        path: AppRoutes.clientNotifications,
        name: AppRoutes.clientNotificationsName,
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: AppRoutes.dietPlanDetails,
        name: AppRoutes.dietPlanDetailsName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.dietPlan,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.messageThread,
        name: AppRoutes.messageThreadName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.message,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.taskDetails,
        name: AppRoutes.taskDetailsName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.task,
          referenceId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.paymentDetails,
        name: AppRoutes.paymentDetailsName,
        builder: (context, state) => NotificationDestinationPage(
          type: NotificationType.payment,
          referenceId: state.pathParameters['id']!,
        ),
      ),
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
