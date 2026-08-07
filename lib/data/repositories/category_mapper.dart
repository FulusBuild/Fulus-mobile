import 'package:drift/drift.dart';

import '../../domain/entities/category.dart';
import '../local/database/database.dart';
import '../local/database/tables.dart';

extension CategoryToCompanion on Category {
  CategoriesCompanion toDriftCompanion() {
    return CategoriesCompanion.insert(
      localId: localId,
      name: name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pending,
      serverId: Value(serverId),
      description: Value(description),
      deletedAt: const Value(null),
    );
  }

  /// No `clientReference` param — unlike Customer/Sale's equivalent
  /// method, `CategoryCreateDto` genuinely has no field for one; see
  /// that DTO's own doc comment for the confirmed backend gap this
  /// reflects rather than works around.
  CategoryCreateDto toCreateDto() {
    return CategoryCreateDto(name: name, description: description);
  }
}

extension CategoryRowToDomain on CategoryRow {
  Category toDomain() {
    return Category(
      localId: localId,
      serverId: serverId,
      name: name,
      description: description,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }
}
