import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus/data/local/database/database.dart';
import 'package:fulus/data/repositories/sale_canonical_repository_impl.dart';
import 'package:fulus/domain/entities/sale_canonical_state.dart';

void main() {
  test('two independent SQLite runtimes converge on the same canonical financial sale', () async {
    final deviceA = AppDatabase.forTesting(NativeDatabase.memory());
    final deviceB = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(deviceA.close);
    addTearDown(deviceB.close);

    await _seedLocation(deviceA, 'loc-a', 'location-server-1');
    await _seedLocation(deviceB, 'loc-b', 'location-server-1');

    final now = DateTime.utc(2026, 10, 3, 12);
    final state = SaleCanonicalState(
      serverId: 'sale-server-1',
      clientReference: 'p16-sale-1',
      invoiceNumber: 'INV-P16-1',
      customerServerId: null,
      locationServerId: 'location-server-1',
      cashierUserId: null,
      saleDate: now,
      subtotal: 150,
      discount: 0,
      tax: 0,
      total: 150,
      amountPaid: 0,
      paymentMethod: 'credit',
      notes: 'P16 two-runtime convergence',
      items: const [
        SaleCanonicalItem(
          serverId: 'sale-item-server-1',
          productServerId: null,
          description: 'P16 quick sale',
          quantity: 1,
          unitPrice: 150,
          costPriceAtSale: 0,
          lineTotal: 150,
        ),
      ],
      payments: [
        SaleCanonicalPayment(
          serverId: 'payment-server-1',
          method: 'credit',
          amount: 150,
          recordedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );

    await SaleCanonicalRepositoryImpl(db: deviceA).reconcileServerState(state);
    await SaleCanonicalRepositoryImpl(db: deviceB).reconcileServerState(state);

    final saleA = await (deviceA.select(deviceA.sales)
          ..where((row) => row.serverId.equals('sale-server-1')))
        .getSingle();
    final saleB = await (deviceB.select(deviceB.sales)
          ..where((row) => row.serverId.equals('sale-server-1')))
        .getSingle();

    expect(saleA.total, saleB.total);
    expect(saleA.amountPaid, saleB.amountPaid);
    expect(saleA.paymentMethod, saleB.paymentMethod);
    expect(saleA.locationId, 'loc-a');
    expect(saleB.locationId, 'loc-b');

    final itemsA = await (deviceA.select(deviceA.saleItems)
          ..where((row) => row.saleLocalId.equals(saleA.localId)))
        .get();
    final itemsB = await (deviceB.select(deviceB.saleItems)
          ..where((row) => row.saleLocalId.equals(saleB.localId)))
        .get();

    expect(itemsA, hasLength(1));
    expect(itemsB, hasLength(1));
    expect(itemsA.single.quantity, itemsB.single.quantity);
    expect(itemsA.single.unitPrice, itemsB.single.unitPrice);
    expect(itemsA.single.description, itemsB.single.description);

    final paymentsA = await (deviceA.select(deviceA.salePayments)
          ..where((row) => row.saleLocalId.equals(saleA.localId)))
        .get();
    final paymentsB = await (deviceB.select(deviceB.salePayments)
          ..where((row) => row.saleLocalId.equals(saleB.localId)))
        .get();

    expect(paymentsA, hasLength(1));
    expect(paymentsB, hasLength(1));
    expect(paymentsA.single.method, paymentsB.single.method);
    expect(paymentsA.single.amount, paymentsB.single.amount);
  });
}

Future<void> _seedLocation(
  AppDatabase db,
  String localId,
  String serverId,
) async {
  final now = DateTime.utc(2026, 10, 3, 12);
  await db.into(db.locations).insert(
        LocationsCompanion.insert(
          localId: localId,
          serverId: Value(serverId),
          name: 'P16',
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.settled,
          deletedAt: const Value(null),
        ),
      );
}
