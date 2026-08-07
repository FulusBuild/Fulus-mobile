import 'package:drift/drift.dart';

import '../../domain/entities/supplier.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension SupplierToCompanion on Supplier {
  SuppliersCompanion toDriftCompanion() {
    return SuppliersCompanion.insert(
      localId: localId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      outstandingBalance: Value(outstandingBalance),
      deletedAt: const Value(null),
    );
  }

  /// Same "no clientReference" status as CategoryToCompanion.toCreateDto.
  SupplierCreateDto toCreateDto() {
    return SupplierCreateDto(name: name, phone: phone, email: email, address: address);
  }
}

extension SupplierRowToDomain on SupplierRow {
  Supplier toDomain() {
    return Supplier(
      localId: localId,
      serverId: serverId,
      name: name,
      phone: phone,
      email: email,
      address: address,
      outstandingBalance: outstandingBalance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
