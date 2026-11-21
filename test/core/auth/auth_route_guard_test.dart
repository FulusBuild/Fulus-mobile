import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/core/auth/auth_route_guard.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';

void main() {
  const owner = AuthUser(
    id: 'owner-local-id',
    username: 'owner',
    email: 'owner@example.test',
    fullName: 'QA Owner',
    role: AuthRole.owner,
    isActive: true,
    hasLoginPin: false,
  );

  test('signed-in identities cannot enter the employee login route', () {
    expect(
      redirectSignedInUserFromLogin(user: owner, matchedLocation: '/login'),
      '/',
    );
  });

  test('signed-in identities leave the signed-out welcome route', () {
    expect(
      redirectSignedInUserFromLogin(user: owner, matchedLocation: '/welcome'),
      '/',
    );
  });

  test('signed-in identities may remain on other routes', () {
    expect(
      redirectSignedInUserFromLogin(user: owner, matchedLocation: '/'),
      isNull,
    );
  });

  test('signed-out users can enter the employee login route', () {
    expect(
      redirectSignedInUserFromLogin(user: null, matchedLocation: '/login'),
      isNull,
    );
  });
}
