import 'package:json_annotation/json_annotation.dart';

part 'category.g.dart';

/// A product category — see tables.dart's `Categories` table doc comment
/// for why this is new in this pass rather than something the earlier
/// Foundation phase built (a real, confirmed backend gap: the endpoint
/// existed all along, verified directly against
/// backend/app/services/inventory_service.py and
/// backend/app/routers/inventory.py; nothing on mobile called it until
/// now).
class Category {
  const Category({
    required this.localId,
    this.serverId,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Fields needed to create a [Category]. **No `clientReference`** —
/// checked directly against `backend/app/schemas/inventory.py`'s
/// `CategoryCreate`, which is a bare `CategoryBase` with no extra
/// fields at all, unlike `CustomerCreate`/`SaleCreate`. This is a real,
/// confirmed gap on the *backend* side, not a mobile omission: category/
/// supplier creation has no idempotency key, so a sync retry after a
/// dropped response (server processed it, mobile never saw the reply)
/// can create a genuine duplicate category server-side. Pydantic's
/// default `extra="ignore"` config means sending a `client_reference`
/// anyway wouldn't break the request, just silently do nothing — so it's
/// left off entirely rather than included as a field that implies
/// protection that isn't actually there.
class CategoryDraft {
  const CategoryDraft({required this.name, this.description});

  final String name;
  final String? description;

  Category toCategoryEntity({required String localId}) {
    final now = DateTime.now();
    return Category(
      localId: localId,
      name: name,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
  }
}

@JsonSerializable(fieldRename: FieldRename.snake, createFromJson: false)
class CategoryCreateDto {
  const CategoryCreateDto({required this.name, this.description});

  final String name;
  final String? description;

  Map<String, dynamic> toJson() => _$CategoryCreateDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class CategoryResponseDto {
  const CategoryResponseDto({
    required this.id,
    required this.name,
    this.description,
  });

  final String id;
  final String name;
  final String? description;

  factory CategoryResponseDto.fromJson(Map<String, dynamic> json) =>
      _$CategoryResponseDtoFromJson(json);
}
