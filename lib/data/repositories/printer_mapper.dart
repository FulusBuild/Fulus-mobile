import 'package:drift/drift.dart';

import '../../domain/entities/printer_device.dart';
import '../local/database/database.dart';

extension PairedPrinterToCompanion on PairedPrinter {
  PairedPrintersCompanion toDriftCompanion() {
    return PairedPrintersCompanion.insert(
      id: id,
      name: name,
      address: address,
      transport: transport,
      pairedAt: pairedAt,
      isDefault: Value(isDefault),
    );
  }
}

extension PairedPrinterRowToDomain on PairedPrinterRow {
  PairedPrinter toDomain() {
    return PairedPrinter(
      id: id,
      name: name,
      address: address,
      transport: transport,
      isDefault: isDefault,
      pairedAt: pairedAt,
    );
  }
}
