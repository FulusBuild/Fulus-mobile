import 'package:fulus_mobile/core/errors/failure.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/endpoints/business_settings_api.dart';
import 'package:fulus_mobile/data/repositories/business_settings_repository_impl.dart';
import 'package:fulus_mobile/data/repositories/permission_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/domain/entities/business_category.dart';
import 'package:fulus_mobile/domain/entities/business_settings.dart';
import 'package:fulus_mobile/domain/repositories/auth_repository.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/db_seed_helpers.dart';

class MockBusinessSettingsApi extends Mock implements BusinessSettingsApi {}

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late AppDatabase db;
  late MockBusinessSettingsApi businessSettingsApi;
  late MockAuthRepository authRepository;
  late PermissionRepositoryImpl permissionRepository;
  late BusinessSettingsRepositoryImpl repository;
  late SyncExecutionLease executionLease;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    businessSettingsApi = MockBusinessSettingsApi();
    authRepository = MockAuthRepository();
    permissionRepository = PermissionRepositoryImpl(db: db);
    executionLease = SyncExecutionLease(db);
    repository = BusinessSettingsRepositoryImpl(
      db: db,
      businessSettingsApi: businessSettingsApi,
      authRepository: authRepository,
      permissionRepository: permissionRepository,
      executionLease: executionLease,
    );
  });

  tearDown(() async {
    await executionLease.release();
    await db.close();
  });

  test('waits for the shared sync lease before clearing business data', () async {
    await repository.createBusiness(
      businessName: 'Lease Guard Store',
      category: BusinessCategory.retailShop,
      currencySymbol: '₦',
    );
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'pending-reset-guard',
        entityType: 'product',
        entityLocalId: 'product-reset-guard',
        operation: 'create',
        priority: 0,
        enqueuedAt: DateTime.now(),
      ),
    );

    final blocker = SyncExecutionLease(
      db,
      acquisitionTimeout: const Duration(seconds: 2),
    );
    addTearDown(blocker.release);
    expect(await blocker.acquire(), isTrue);

    final clearing = repository.clearLocalBusinessData();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(await repository.hasBeenConfigured(), isTrue);
    expect(await db.select(db.syncQueueItems).get(), isNotEmpty);

    await blocker.release();
    await clearing;

    expect(await repository.hasBeenConfigured(), isFalse);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
  });

  group('watchSettings', () {
    test('emits null before the first sync', () async {
      final settings = await repository.watchSettings().first;
      expect(settings, isNull);
    });
  });

  group('hasBeenConfigured', () {
    test('false on a fresh install', () async {
      expect(await repository.hasBeenConfigured(), isFalse);
    });

    test('true once a business has been created', () async {
      await repository.createBusiness(
        businessName: 'Chidinma\'s Store',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );
      expect(await repository.hasBeenConfigured(), isTrue);
    });
  });

  group('createBusiness', () {
    test('creates the singleton row entirely locally, with no API call at all',
        () async {
      await repository.createBusiness(
        businessName: 'Chidinma\'s Store',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );

      final settings = await repository.watchSettings().first;
      expect(settings, isNotNull);
      expect(settings!.businessName, 'Chidinma\'s Store');
      expect(settings.currencySymbol, '\u20a6');

      verifyNever(() => businessSettingsApi.getBusinessProfile());
    });

    test('rejects a second call once a business already exists', () async {
      await repository.createBusiness(
        businessName: 'Chidinma\'s Store',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );

      await expectLater(
        repository.createBusiness(
          businessName: 'Someone Else\'s Store',
          category: BusinessCategory.pharmacy,
          currencySymbol: '\u20a6',
        ),
        throwsA(isA<BusinessRuleFailure>()),
      );
    });

    test('rejects an empty business name', () async {
      await expectLater(
        repository.createBusiness(
          businessName: '',
          category: BusinessCategory.retailShop,
          currencySymbol: '\u20a6',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('updateSettings', () {
    setUp(() async {
      await repository.createBusiness(
        businessName: 'Chidinma\'s Store',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );
    });

    test('an owner can update the profile', () async {
      when(() => authRepository.currentUser).thenReturn(
        const AuthUser(
          id: 'user-1',
          username: 'chidinma',
          email: 'chidinma@example.com',
          fullName: 'Chidinma Okafor',
          role: AuthRole.owner,
          isActive: true,
          hasLoginPin: true,
        ),
      );

      await repository.updateSettings(
        businessName: 'Chidinma\'s Store (Renamed)',
        vatEnabled: true,
        vatRate: 7.5,
        currencySymbol: '\u20a6',
        receiptFooter: 'Thank you for your patronage',
      );

      final settings = await repository.watchSettings().first;
      expect(settings!.businessName, 'Chidinma\'s Store (Renamed)');
      expect(settings.vatEnabled, isTrue);
      expect(settings.receiptFooter, 'Thank you for your patronage');
    });

    test('rejects the call from a non-owner — the local check IS the real enforcement now',
        () async {
      when(() => authRepository.currentUser).thenReturn(
        const AuthUser(
          id: 'user-2',
          username: 'employee1',
          email: 'employee1@example.com',
          fullName: 'An Employee',
          role: AuthRole.employee,
          isActive: true,
          hasLoginPin: true,
        ),
      );

      await expectLater(
        repository.updateSettings(
          businessName: 'Hijacked Name',
          vatEnabled: false,
          vatRate: 0,
          currencySymbol: '\u20a6',
        ),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('rejects a VAT rate outside 0-100, mirroring schemas/settings.py exactly',
        () async {
      when(() => authRepository.currentUser).thenReturn(
        const AuthUser(
          id: 'user-1',
          username: 'chidinma',
          email: 'chidinma@example.com',
          fullName: 'Chidinma Okafor',
          role: AuthRole.owner,
          isActive: true,
          hasLoginPin: true,
        ),
      );

      await expectLater(
        repository.updateSettings(
          businessName: 'Chidinma\'s Store',
          vatEnabled: true,
          vatRate: 150,
          currencySymbol: '\u20a6',
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });
  });

  group('syncFromServer', () {
    test('writes the singleton row on first sync, including all four previously-missing fields', () async {
      when(() => businessSettingsApi.getBusinessProfile()).thenAnswer(
        (_) async => const BusinessSettingsResponseDto(
          id: 'server-id-1',
          businessName: 'Fatima Stores',
          address: '14 Marina Road, Lagos',
          phone: '+2348012345678',
          email: 'owner@fatimastores.com',
          tin: 'TIN-00012345',
          vatEnabled: true,
          vatRate: 7.5,
          currencySymbol: '\u20a6',
          receiptFooter: 'Thank you for your patronage',
        ),
      );

      await repository.syncFromServer();

      final settings = await repository.watchSettings().first;
      expect(settings, isNotNull);
      expect(settings!.businessName, 'Fatima Stores');
      expect(settings.address, '14 Marina Road, Lagos');
      expect(settings.phone, '+2348012345678');
      expect(settings.email, 'owner@fatimastores.com');
      expect(settings.tin, 'TIN-00012345');
      expect(settings.vatEnabled, isTrue);
      expect(settings.vatRate, 7.5);
      expect(settings.currencySymbol, '\u20a6');
      expect(settings.receiptFooter, 'Thank you for your patronage');
    });

    test('handles all four nullable fields genuinely being null', () async {
      // Not a hypothetical — the backend's BusinessProfileOut declares
      // address/phone/email/tin as `str | None` with no defaults, so a
      // business that hasn't filled them in yet returns exactly this.
      when(() => businessSettingsApi.getBusinessProfile()).thenAnswer(
        (_) async => const BusinessSettingsResponseDto(
          id: 'server-id-1',
          businessName: 'Fatima Stores',
          vatEnabled: false,
          vatRate: 0,
          currencySymbol: '\u20a6',
        ),
      );

      await repository.syncFromServer();

      final settings = await repository.watchSettings().first;
      expect(settings!.address, isNull);
      expect(settings.phone, isNull);
      expect(settings.email, isNull);
      expect(settings.tin, isNull);
    });

    test('re-syncing updates the single row rather than creating a second one', () async {
      when(() => businessSettingsApi.getBusinessProfile()).thenAnswer(
        (_) async => const BusinessSettingsResponseDto(
          id: 'server-id-1',
          businessName: 'Fatima Stores',
          vatEnabled: false,
          vatRate: 0,
          currencySymbol: '\u20a6',
        ),
      );
      await repository.syncFromServer();

      when(() => businessSettingsApi.getBusinessProfile()).thenAnswer(
        (_) async => const BusinessSettingsResponseDto(
          id: 'server-id-1',
          businessName: 'Fatima Stores (Renamed)',
          vatEnabled: true,
          vatRate: 10,
          currencySymbol: '\u20a6',
        ),
      );
      await repository.syncFromServer();

      final rows = await db.select(db.businessSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.businessName, 'Fatima Stores (Renamed)');
      expect(rows.single.vatRate, 10);
    });

    test('always writes to the fixed singleton id regardless of the backend\'s real id', () async {
      when(() => businessSettingsApi.getBusinessProfile()).thenAnswer(
        (_) async => const BusinessSettingsResponseDto(
          id: 'whatever-uuid-the-backend-happens-to-have',
          businessName: 'Fatima Stores',
          vatEnabled: false,
          vatRate: 0,
          currencySymbol: '\u20a6',
        ),
      );

      await repository.syncFromServer();

      final rows = await db.select(db.businessSettings).get();
      expect(rows.single.id, 'singleton');
    });
  });

  group('clearLocalBusinessData — Restore Progress "Start Fresh"', () {
    test('removes the singleton row, so hasBeenConfigured is false again', () async {
      await repository.createBusiness(
        businessName: 'Orphaned Business',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );
      expect(await repository.hasBeenConfigured(), isTrue);

      await repository.clearLocalBusinessData();

      expect(await repository.hasBeenConfigured(), isFalse);
      final rows = await db.select(db.businessSettings).get();
      expect(rows, isEmpty);
    });

    test('a fresh createBusiness call succeeds afterward — the whole point of '
        'Start Fresh, matching the exact state a genuinely new install starts from',
        () async {
      await repository.createBusiness(
        businessName: 'Orphaned Business',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );

      await repository.clearLocalBusinessData();

      await repository.createBusiness(
        businessName: 'Brand New Business',
        category: BusinessCategory.pharmacy,
        currencySymbol: '\u20a6',
      );

      final settings = await repository.watchSettings().first;
      expect(settings!.businessName, 'Brand New Business');
    });

    test('also clears related tables (locations), not just the singleton row',
        () async {
      await repository.createBusiness(
        businessName: 'Orphaned Business',
        category: BusinessCategory.retailShop,
        currencySymbol: '\u20a6',
      );
      await seedLocation(db, name: 'Main Shop');
      expect(await db.select(db.locations).get(), isNotEmpty);

      await repository.clearLocalBusinessData();

      expect(await db.select(db.locations).get(), isEmpty);
    });
  });
}
