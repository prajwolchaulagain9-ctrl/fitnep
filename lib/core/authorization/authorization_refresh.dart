import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthorizationRefresh extends Notifier<int> {
  @override
  int build() => 0;
  void refresh() => state++;
}

final authorizationRefreshProvider =
    NotifierProvider<AuthorizationRefresh, int>(AuthorizationRefresh.new);
final authorizationEpochProvider = NotifierProvider<AuthorizationRefresh, int>(
  AuthorizationRefresh.new,
);
