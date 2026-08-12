import 'package:fulus_mobile/domain/entities/business_settings.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/domain/repositories/business_settings_repository.dart';
import 'package:fulus_mobile/domain/repositories/location_repository.dart';
import 'package:fulus_mobile/domain/usecases/active_location_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocationRepository extends Mock implements LocationRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class MockBusinessSettingsRepository extends Mock implements BusinessSettingsRepository {}

void main() {
  late MockLocationRepository locationRepository;
  late MockAuthRepository authRepository;
  late MockBusinessSettingsRepository businessSettingsRepository;
  late ResolveActiveLocation resolver;

  final now = DateTime(2026, 1, 1);

  Location fakeLocation(String localId, {String name = 'Main Location'}) {
    return Location(localId: localId, name: name, createdAt: now, updatedAt: now);
  }

  BusinessProfile fakeProfile(String businessName) {
    return BusinessProfile(
      businessName: businessName,
      currencySymbol: '₦',
      vatEnabled: false,
      vatRate: 0,
      updatedAt: now,
    );
  }

  setUp(() {
    locationRepository = MockLocationRepository();
    authRepository = MockAuthRepository();
    businessSettingsRepository = MockBusinessSettingsRepository();
    resolver = ResolveActiveLocation(
      locationRepository: locationRepository,
      authRepository: authRepository,
      businessSettingsRepository: businessSettingsRepository,
    );
  });

  test('reuses the stored active location when it still exists', () async {
    when(() => authRepository.getActiveLocationId()).thenAnswer((_) async => 'loc-1');
    when(() => locationRepository.getLocationById('loc-1'))
        .thenAnswer((_) async => fakeLocation('loc-1'));

    final result = await resolver.call();

    expect(result, 'loc-1');
    // No re-resolution needed — the stored id was still valid, so
    // nothing should have been (re-)persisted or (re-)created.
    verifyNever(() => authRepository.setActiveLocationId(any()));
    verifyNever(() => locationRepository.getOrCreateDefaultLocation(name: any(named: 'name')));
  });

  test('re-resolves when the stored location no longer exists', () async {
    when(() => authRepository.getActiveLocationId()).thenAnswer((_) async => 'loc-deleted');
    when(() => locationRepository.getLocationById('loc-deleted')).thenAnswer((_) async => null);
    when(() => businessSettingsRepository.watchSettings())
        .thenAnswer((_) => Stream.value(fakeProfile("Ngozi's Store")));
    when(() => locationRepository.getOrCreateDefaultLocation(name: any(named: 'name')))
        .thenAnswer((_) async => fakeLocation('loc-new'));
    when(() => authRepository.setActiveLocationId(any())).thenAnswer((_) async {});

    final result = await resolver.call();

    expect(result, 'loc-new');
    verify(() => authRepository.setActiveLocationId('loc-new')).called(1);
  });

  test('seeds a location named after the business when nothing is stored yet', () async {
    when(() => authRepository.getActiveLocationId()).thenAnswer((_) async => null);
    when(() => businessSettingsRepository.watchSettings())
        .thenAnswer((_) => Stream.value(fakeProfile("Ngozi's Store")));
    when(() => locationRepository.getOrCreateDefaultLocation(name: any(named: 'name')))
        .thenAnswer((_) async => fakeLocation('loc-new', name: "Ngozi's Store"));
    when(() => authRepository.setActiveLocationId(any())).thenAnswer((_) async {});

    final result = await resolver.call();

    expect(result, 'loc-new');
    verify(() => locationRepository.getOrCreateDefaultLocation(name: "Ngozi's Store")).called(1);
    verify(() => authRepository.setActiveLocationId('loc-new')).called(1);
  });

  test('falls back to a default name when no business profile exists yet', () async {
    when(() => authRepository.getActiveLocationId()).thenAnswer((_) async => null);
    when(() => businessSettingsRepository.watchSettings())
        .thenAnswer((_) => Stream.value(null));
    when(() => locationRepository.getOrCreateDefaultLocation(name: any(named: 'name')))
        .thenAnswer((_) async => fakeLocation('loc-new', name: 'Main Location'));
    when(() => authRepository.setActiveLocationId(any())).thenAnswer((_) async {});

    await resolver.call();

    verify(() => locationRepository.getOrCreateDefaultLocation(name: 'Main Location')).called(1);
  });
}
