import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/remote/fulus_connection_state.dart';
import 'package:fulus_mobile/data/remote/fulus_device_registration.dart';
import 'package:fulus_mobile/data/remote/fulus_sync_api.dart';
import 'package:fulus_mobile/domain/entities/cash_drawer_shift.dart';
import 'package:fulus_mobile/domain/entities/location.dart';
import 'package:fulus_mobile/domain/repositories/cash_drawer_shift_repository.dart';
import 'package:fulus_mobile/domain/repositories/location_repository.dart';
import 'package:fulus_mobile/sync/handlers/cash_drawer_shift_sync_handler.dart';
import 'package:fulus_mobile/sync/sync_execution_lease.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFulusSyncApi extends Mock implements FulusSyncApi {}
class MockFulusConnectionState extends Mock implements FulusConnectionState {}
class MockCashDrawerShiftRepository extends Mock implements CashDrawerShiftRepository {}
class MockLocationRepository extends Mock implements LocationRepository {}

void main() {
  late MockFulusSyncApi fulusSyncApi;
  late MockFulusConnectionState connectionState;
  late MockCashDrawerShiftRepository repository;
  late MockLocationRepository locationRepository;
  late CashDrawerShiftSyncHandler handler;
  late AppDatabase db;
  late SyncExecutionLease executionLease;

  final opened = DateTime(2026, 9, 15, 8);
  final closed = DateTime(2026, 9, 15, 18);
  final shift = CashDrawerShift(
    localId: 'shift-local-1',
    serverId: 'shift-server-1',
    cashierUserId: 'user-1',
    locationId: 'loc-1',
    openedAt: opened,
    closedAt: closed,
    openingCash: 10000,
    closingCash: 18500,
    cashDifference: 500,
    closingNote: 'Balanced',
    closingSummaryLocked: true,
  );
  final location = Location(
    localId: 'loc-1',
    serverId: 'server-location-1',
    name: 'Main Store',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    executionLease = SyncExecutionLease(db);
    fulusSyncApi = MockFulusSyncApi();
    connectionState = MockFulusConnectionState();
    repository = MockCashDrawerShiftRepository();
    locationRepository = MockLocationRepository();
    handler = CashDrawerShiftSyncHandler(
      db: db,
      fulusSyncApi: fulusSyncApi,
      fulusConnectionState: connectionState,
      executionLease: executionLease,
      cashDrawerShiftRepository: repository,
      locationRepository: locationRepository,
    );
    when(() => connectionState.selectedBusinessId).thenReturn('business-1');
    when(() => connectionState.registeredDevice).thenReturn(const FulusRegisteredDevice(
      id: 'device-1',
      businessId: 'business-1',
      deviceClientId: 'device-client-1',
      status: 'active',
    ));
    when(() => repository.getShiftById('shift-local-1')).thenAnswer((_) async => shift);
    when(() => repository.markSynced(
          localId: any(named: 'localId'),
          serverId: any(named: 'serverId'),
        )).thenAnswer((_) async {});
    when(() => locationRepository.getLocationById('loc-1')).thenAnswer((_) async => location);
  });

  tearDown(() async {
    await executionLease.release();
    await db.close();
  });

  SyncQueueItem item(String operation, {int? baseCursor}) => SyncQueueItem(
        id: operation == 'create' ? 'open-op-1' : 'close-op-1',
        entityType: 'cash_drawer_shift',
        entityLocalId: shift.localId,
        operation: operation,
        priority: 1,
        enqueuedAt: DateTime.now(),
        syncAttempts: 0,
        baseCursor: baseCursor,
      );

  test('pushes shift open through Fulus Cloud and uses server location id', () async {
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
          'data': {'shift_id': 'shift-server-1'},
        });

    await handler.sync(item('create'));

    final captured = verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'cash_drawer_shift.create',
          operationId: 'open-op-1',
          deviceClientId: 'device-client-1',
          clientReference: shift.localId,
          payload: captureAny(named: 'payload'),
        )).captured.single as Map<String, dynamic>;
    expect(captured['location_id'], 'server-location-1');
    verify(() => repository.markSynced(localId: shift.localId, serverId: 'shift-server-1')).called(1);
  });

  test('pushes shift close through Fulus Cloud using the existing server row', () async {
    when(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        )).thenAnswer((_) async => {
          'data': {'shift_id': 'shift-server-1'},
        });

    await handler.sync(item('close', baseCursor: 41));

    final captured = verify(() => fulusSyncApi.submitOperation(
          businessId: 'business-1',
          operationType: 'cash_drawer_shift.close',
          operationId: 'close-op-1',
          deviceClientId: 'device-client-1',
          clientReference: shift.localId,
          payload: captureAny(named: 'payload'),
        )).captured.single as Map<String, dynamic>;
    expect(captured['base_cursor'], 41);
    verify(() => repository.markSynced(localId: shift.localId, serverId: 'shift-server-1')).called(1);
  });

  test('blocks a close when the create has not produced a server id', () async {
    final localOnly = CashDrawerShift(
      localId: shift.localId,
      cashierUserId: shift.cashierUserId,
      locationId: shift.locationId,
      openedAt: shift.openedAt,
      openingCash: shift.openingCash,
    );
    when(() => repository.getShiftById(shift.localId)).thenAnswer((_) async => localOnly);

    await expectLater(handler.sync(item('close')), throwsA(isA<StateError>()));
    verifyNever(() => fulusSyncApi.submitOperation(
          businessId: any(named: 'businessId'),
          operationType: any(named: 'operationType'),
          operationId: any(named: 'operationId'),
          deviceClientId: any(named: 'deviceClientId'),
          clientReference: any(named: 'clientReference'),
          payload: any(named: 'payload'),
        ));
  });
}
