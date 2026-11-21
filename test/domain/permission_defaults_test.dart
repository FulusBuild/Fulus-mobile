import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/permission.dart';

void main() {
  test('cashier preset can sell but does not manage inventory by default', () {
    expect(Permission.defaultsForRole(AuthRole.cashier), isEmpty);
  });

  test('manager retains stock management in the preset', () {
    expect(
      Permission.defaultsForRole(AuthRole.manager),
      contains(Permission.manageStock),
    );
  });
}
