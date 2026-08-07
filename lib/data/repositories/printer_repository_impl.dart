import 'package:drift/drift.dart';
import 'package:ulid/ulid.dart';

import '../../domain/entities/printer_device.dart';
import '../../domain/repositories/printer_repository.dart';
import '../local/database/database.dart';
import 'printer_mapper.dart';

class PrinterRepositoryImpl implements PrinterRepository {
  PrinterRepositoryImpl({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Stream<List<PairedPrinter>> watchPaired() {
    final query = _db.select(_db.pairedPrinters)
      ..orderBy([(t) => OrderingTerm.asc(t.pairedAt)]);
    return query.watch().map((rows) => rows.map((r) => r.toDomain()).toList());
  }

  @override
  Future<PairedPrinter?> getDefault() async {
    final query = _db.select(_db.pairedPrinters)
      ..where((t) => t.isDefault.equals(true));
    final row = await query.getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<PairedPrinter> pair(PrinterDevice device) async {
    return _db.transaction(() async {
      final existing = await _db.select(_db.pairedPrinters).get();
      final printer = PairedPrinter(
        id: Ulid().toString(),
        name: device.name,
        address: device.address,
        transport: device.transport,
        // The first printer ever paired becomes the default
        // automatically — see PrinterRepository.pair's own doc comment
        // on why this specifically checks "is the table empty," not
        // some other heuristic.
        isDefault: existing.isEmpty,
        pairedAt: DateTime.now(),
      );
      await _db.into(_db.pairedPrinters).insert(printer.toDriftCompanion());
      return printer;
    });
  }

  @override
  Future<void> unpair(String id) async {
    await (_db.delete(_db.pairedPrinters)..where((t) => t.id.equals(id))).go();
    // Deliberately NOT auto-promoting another paired printer to default
    // after an unpair, even if one remains — an owner who unpairs their
    // default printer is left with none set, the same honest "nothing
    // selected" state as before any printer was ever paired, rather than
    // this repository silently guessing which of several remaining
    // printers they'd want instead.
  }

  @override
  Future<void> setDefault(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.pairedPrinters)..where((t) => t.isDefault.equals(true)))
          .write(PairedPrintersCompanion(isDefault: Value(false)));
      await (_db.update(_db.pairedPrinters)..where((t) => t.id.equals(id)))
          .write(PairedPrintersCompanion(isDefault: Value(true)));
    });
  }
}
