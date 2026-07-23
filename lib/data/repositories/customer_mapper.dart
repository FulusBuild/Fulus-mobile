import 'package:drift/drift.dart';

import '../../domain/entities/customer.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension CustomerToCompanion on Customer {
  CustomersCompanion toDriftCompanion() {
    return CustomersCompanion.insert(
      localId: localId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      notes: Value(notes),
      outstandingBalance: Value(outstandingBalance),
      deletedAt: const Value(null),
    );
  }
}

extension CustomerRowToDomain on CustomerRow {
  Customer toDomain() {
    return Customer(
      localId: localId,
      serverId: serverId,
      name: name,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
      outstandingBalance: outstandingBalance,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
