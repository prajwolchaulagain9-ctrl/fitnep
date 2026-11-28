import 'package:fitnep/features/authorization/data/account.dart';
import 'package:fitnep/shared/role_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> account(Object? role) => {
  'id': 'client-a',
  'role': role,
  'account_status': 'active',
  'full_name': 'Current User',
  'email': 'a@example.test',
  'created_at': '2026-11-22T00:00:00Z',
  'updated_at': '2026-11-22T00:00:00Z',
};
void main() {
  test('canonical server account roles determine the four dashboards', () {
    for (final role in FitNepRole.values) {
      expect(FitNepAccount.fromJson(account(role.name)).role, role);
      expect(dashboardForRole(role), contains(role.name));
    }
  });
  test('missing, malformed, and multiple roles fail closed', () {
    for (final role in [
      null,
      '',
      'owner',
      ' STAFF ',
      1,
      ['client', 'admin'],
    ]) {
      expect(
        () => FitNepAccount.fromJson(account(role)),
        throwsFormatException,
      );
    }
  });
  test('nonadmin roles cannot gain administrative permissions', () {
    for (final role in [
      FitNepRole.client,
      FitNepRole.staff,
      FitNepRole.dietitian,
    ]) {
      final authorization = AuthorizationService(role);
      expect(authorization.hasPermission('manage_staff_accounts'), isFalse);
      expect(authorization.hasPermission('manage_user_roles'), isFalse);
    }
  });
}
