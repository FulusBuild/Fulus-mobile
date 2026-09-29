import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/app/providers.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/usecases/active_location_resolver.dart';

class MockResolveActiveLocation extends Mock implements ResolveActiveLocation {}

void main() {
  test('active location is re-resolved when the signed-in account changes', () async {
    final resolver = MockResolveActiveLocation();
    var calls = 0;
    when(() => resolver.call()).thenAnswer((_) async {
      calls++;
      return calls == 1 ? 'location-a' : 'location-b';
    });

    final container = ProviderContainer(
      overrides: [
        resolveActiveLocationProvider.overrideWithValue(resolver),
        sessionProvider.overrideWith((ref) => null),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(activeLocationIdProvider.future), 'location-a');
    expect(calls, 1);

    container.read(sessionProvider.notifier).state = const AuthUser(
      id: 'user-b',
      fullName: 'User B',
      role: AuthRole.owner,
      isActive: true,
      hasLoginPin: false,
    );

    expect(await container.read(activeLocationIdProvider.future), 'location-b');
    expect(calls, 2);
  });
}
