import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/app_routes.dart';
import 'controllers/authentication_controller.dart';

Future<bool> signOutToWelcome(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final signedOut = await ref
      .read(authenticationControllerProvider.notifier)
      .signOut();
  if (signedOut) router.goNamed(AppRoutes.welcome);
  return signedOut;
}
