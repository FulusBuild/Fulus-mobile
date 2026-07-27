import 'package:bms_mobile/data/local/database/database.dart';
import 'package:bms_mobile/data/remote/endpoints/business_settings_api.dart';
import 'package:bms_mobile/data/repositories/business_settings_repository_impl.dart';
import 'package:bms_mobile/domain/entities/business_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBusinessSettingsApi extends Mock implements BusinessSettingsApi {}

void main() {
  late AppDatabase db;
  late MockBusinessSettingsApi businessSettingsApi;
  late BusinessSettingsRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    businessSettingsApi = MockBusinessSettingsApi();
    repository = BusinessSettingsRepositoryImpl(
      db: db,
      businessSettingsApi: businessSettingsApi,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('watchSettings', () {
    test('emits null before the first sync', () async {
      final settings = await repository.watchSettings().first;
      expect(settings, isNull);
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
}
