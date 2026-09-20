import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:fulus_mobile/data/remote/fulus_business_context.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';

class MockBusinessContext extends Mock implements FulusBusinessContext {}
class MockDeviceRegistration extends Mock implements FulusDeviceRegistration {}

void main() {
  late MockBusinessContext businessContext;
  late MockDeviceRegistration deviceRegistration;

  setUp(() {
    businessContext = MockBusinessContext();
    deviceRegistration = MockDeviceRegistration();
  });

  FulusMembershipContext memberships(List<FulusBusinessMembership> values) {
    return FulusMembershipContext(
      userId: 'user-1',
      deviceClientId: 'device-1',
      memberships: values,
    );
  }

  FulusBusinessMembership membership(String businessId) {
    return FulusBusinessMembership(
      businessId: businessId,
      roleId: 'owner',
      status: 'active',
      joinedAt: DateTime(2026, 1, 1),
    );
  }

  test('preserves a selected active business when memberships become multiple', () async {
    when(() => businessContext.fetch()).thenAnswer(
      (_) async => memberships([membership('business-a')]),
    );
    final state = FulusConnectionState(
      businessContext: businessContext,
      deviceRegistration: deviceRegistration,
    );

    await state.refresh();
    expect(state.selectedBusinessId, 'business-a');

    when(() => businessContext.fetch()).thenAnswer(
      (_) async => memberships([membership('business-a'), membership('business-b')]),
    );

    await state.refresh();

    expect(state.selectedBusinessId, 'business-a');
  });

  test('does not report sync ready merely because a cloud session is authenticated', () {
    final state = FulusConnectionState(
      businessContext: businessContext,
      deviceRegistration: deviceRegistration,
    );

    state.markSessionAuthenticated();

    expect(state.isSessionAuthenticated, isTrue);
    expect(state.isSyncReady, isFalse);
  });

  test('clearing session authentication preserves the selected business but clears readiness', () async {
    when(() => businessContext.fetch()).thenAnswer(
      (_) async => memberships([membership('business-a')]),
    );
    when(() => deviceRegistration.register(
          businessId: 'business-a',
          deviceClientId: 'device-1',
          deviceName: any(named: 'deviceName'),
          platform: any(named: 'platform'),
          appVersion: any(named: 'appVersion'),
        )).thenAnswer(
      (_) async => const FulusRegisteredDevice(
        id: 'registered-1',
        businessId: 'business-a',
        deviceClientId: 'device-1',
        status: 'active',
      ),
    );

    final state = FulusConnectionState(
      businessContext: businessContext,
      deviceRegistration: deviceRegistration,
    );

    await state.refresh();
    state.markSessionAuthenticated();
    await state.registerDevice(deviceClientId: 'device-1');
    state.markSyncReady();

    expect(state.isSyncReady, isTrue);

    state.clearSessionAuthentication();

    expect(state.isSessionAuthenticated, isFalse);
    expect(state.selectedBusinessId, 'business-a');
    expect(state.isSyncReady, isFalse);
  });
}
