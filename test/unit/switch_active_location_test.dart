import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/domain/repositories/location_repository.dart';
import 'package:fulus_mobile/domain/usecases/switch_active_location.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationRepository extends Mock implements LocationRepository {}
class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockLocationRepository locationRepository;
  late MockAuthRepository authRepository;
  final now = DateTime(2026, 1, 1);

  Location location(String id, {DateTime? deletedAt}) => Location(
        localId: id,
        name: id,
        createdAt: now,
        updatedAt: now,
        deletedAt: deletedAt,
      );

  setUp(() {
    locationRepository = MockLocationRepository();
    authRepository = MockAuthRepository();
    when(() => authRepository.getActiveLocationId()).thenAnswer((_) async => 'loc-a');
    when(() => authRepository.setActiveLocationId(any())).thenAnswer((_) async {});
  });

  test('switches only to an existing non-deleted cached location', () async {
    when(() => locationRepository.getLocationById('loc-b'))
        .thenAnswer((_) async => location('loc-b'));

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    await expectLater(switcher('loc-b'), completion('loc-b'));

    verify(() => authRepository.setActiveLocationId('loc-b')).called(1);
  });

  test('fails clearly when the requested location is not cached', () async {
    when(() => locationRepository.getLocationById('loc-b'))
        .thenAnswer((_) async => null);

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    await expectLater(
      switcher('loc-b'),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('not available on this device'),
      )),
    );

    verifyNever(() => authRepository.setActiveLocationId('loc-b'));
  });


  test('switches to a cached location without requiring a network lookup', () async {
    when(() => locationRepository.getLocationById('loc-b'))
        .thenAnswer((_) async => location('loc-b'));

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    await switcher('loc-b');

    verify(() => locationRepository.getLocationById('loc-b')).called(1);
    verify(() => authRepository.setActiveLocationId('loc-b')).called(1);
  });

  test('uncached offline target leaves the current location active', () async {
    var activeLocation = 'loc-a';
    when(() => locationRepository.getLocationById('loc-b'))
        .thenAnswer((_) async => null);
    when(() => authRepository.getActiveLocationId())
        .thenAnswer((_) async => activeLocation);
    when(() => authRepository.setActiveLocationId(any())).thenAnswer((invocation) async {
      activeLocation = invocation.positionalArguments.single as String;
    });

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    await expectLater(
      switcher('loc-b'),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('not available on this device'),
      )),
    );

    expect(activeLocation, 'loc-a');
    verifyNever(() => authRepository.setActiveLocationId('loc-b'));
  });

  test('refuses a deleted location instead of making it active', () async {
    when(() => locationRepository.getLocationById('loc-b'))
        .thenAnswer((_) async => location('loc-b', deletedAt: now));

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    await expectLater(switcher('loc-b'), throwsA(isA<StateError>()));
    verifyNever(() => authRepository.setActiveLocationId('loc-b'));
  });

  test('serializes rapid switches so session writes cannot race', () async {
    final firstLookup = Completer<Location?>();
    when(() => locationRepository.getLocationById('loc-b'))
        .thenAnswer((_) => firstLookup.future);
    when(() => locationRepository.getLocationById('loc-a'))
        .thenAnswer((_) async => location('loc-a'));

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    final first = switcher('loc-b');
    final second = switcher('loc-a');
    await Future<void>.delayed(Duration.zero);

    verify(() => locationRepository.getLocationById('loc-b')).called(1);
    verifyNever(() => locationRepository.getLocationById('loc-a'));

    firstLookup.complete(location('loc-b'));
    await first;
    await second;

    verifyInOrder([
      () => authRepository.setActiveLocationId('loc-b'),
      () => authRepository.setActiveLocationId('loc-a'),
    ]);
  });

  test('switching to the already-active location is a no-op', () async {
    when(() => locationRepository.getLocationById('loc-a'))
        .thenAnswer((_) async => location('loc-a'));

    final switcher = SwitchActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
    );

    await switcher('loc-a');

    verifyNever(() => authRepository.setActiveLocationId('loc-a'));
  });
}
