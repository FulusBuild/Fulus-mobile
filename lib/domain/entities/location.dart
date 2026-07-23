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
