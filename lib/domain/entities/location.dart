import 'package:json_annotation/json_annotation.dart';

part 'location.g.dart';

/// Mirrors the Locations table (tables.dart) — a business's physical
/// locations. Originally modeled as business-wide, desktop-managed per
/// Architecture Section 7a's own framing ("a location switcher... an
/// owner can change this at will") — but that framing assumed a
/// desktop companion always exists to do the creating, which isn't
/// true for a mobile-only business (Volume 1: "Fulus Mobile IS the
/// business system," desktop is an optional companion, not a
/// requirement). Mobile now creates locations too — see
/// [LocationRepository.createLocation] and
/// [LocationRepository.getOrCreateDefaultLocation] — while still
/// consuming any location a desktop companion creates via
/// [LocationRepository.syncFromServer], same as before. Deliberately a
/// thin entity: name is the only catalog field this table has beyond
/// the SyncableColumns mixin.
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

/// What a mobile-created location needs — just a name, matching
/// [Location]'s own deliberately thin shape. No `clientReference`: same
/// status as `SupplierDraft`/`CategoryDraft`, not yet checked against a
/// `LocationCreate` backend schema (see [LocationCreateDto]'s own doc
/// comment for why).
class LocationDraft {
  const LocationDraft({required this.name});

  final String name;

  Location toLocationEntity({required String localId}) {
    final now = DateTime.now();
    return Location(localId: localId, name: name, createdAt: now, updatedAt: now);
  }
}

/// The wire shape for creating a location — mirrors
/// [LocationResponseDto]'s field-naming convention
/// (`fieldRename: FieldRename.snake`) for consistency with the rest of
/// this entity, but **not verified against a backend `POST
/// /api/locations` schema** the way [LocationResponseDto] was verified
/// against `LocationOut` — backend/app/routers/locations.py wasn't
/// available to check against in the pass that added this (see
/// [LocationsApi.createLocation]'s own doc comment for the exact same
/// caveat, stated once and referenced rather than repeated). Modeled by
/// close analogy to `SupplierCreateDto`/`CategoryCreateDto` (both bare
/// name-only creates against this same backend), which is the best
/// available evidence without the router source itself.
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class LocationCreateDto {
  const LocationCreateDto({required this.name});

  final String name;

  Map<String, dynamic> toJson() => _$LocationCreateDtoToJson(this);
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
