import 'package:json_annotation/json_annotation.dart';

part 'location.g.dart';

/// Mirrors the Locations table (tables.dart) — business-wide, desktop-
/// managed per Architecture Section 7a ("a location switcher... an
/// owner can change this at will"), not something a mobile device
/// creates. Deliberately a thin entity: name is the only catalog field
/// this table has beyond the SyncableColumns mixin.
class Location {
  const Location({
    required this.localId,
    this.serverId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// Mirrors backend/app/schemas/location.py's LocationOut exactly,
/// verified directly — the response body for GET /api/locations,
/// added to the backend for the first time alongside this class (the
/// backend previously had zero location infrastructure at all; see the
/// mobile handoff doc's Section 7 discrepancy table, corrected there
/// rather than silently). Deliberately no createToJson — this DTO only
/// ever flows server -> mobile, the same one-directional shape as
/// ProductResponseDto/ProductListResponseDto in product.dart.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class LocationResponseDto {
  const LocationResponseDto({required this.id, required this.name});

  final String id;
  final String name;

  factory LocationResponseDto.fromJson(Map<String, dynamic> json) =>
      _$LocationResponseDtoFromJson(json);
}
