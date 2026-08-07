import 'package:json_annotation/json_annotation.dart';

part 'supplier.g.dart';

/// A supplier — see tables.dart's `Suppliers` table doc comment and
/// `Categories`' own doc comment in `category.dart` for the shared
/// "real, confirmed backend gap, new in this pass" status both tables
/// have.
class Supplier {
  const Supplier({
    required this.localId,
    this.serverId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.outstandingBalance = 0.0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String localId;
  final String? serverId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;

  /// **Bible-only** (Volume 8, Decision 26 — see
  /// `SupplierLedgerEntries`' own doc comment in tables.dart for the
  /// full no-backend-column gap). What the business currently owes this
  /// supplier. Mutated only through `SupplierCreditRepository`'s
  /// methods, never a raw field update — same discipline
  /// `Customer.outstandingBalance` follows.
  final double outstandingBalance;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// **No `clientReference`** — same confirmed gap as `CategoryDraft`,
/// checked directly against the same `SupplierCreate` schema (a bare
/// `SupplierBase`, no extra fields).
class SupplierDraft {
  const SupplierDraft({
    required this.name,
    this.phone,
    this.email,
    this.address,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;

  Supplier toSupplierEntity({required String localId}) {
    final now = DateTime.now();
    return Supplier(
      localId: localId,
      name: name,
      phone: phone,
      email: email,
      address: address,
      createdAt: now,
      updatedAt: now,
    );
  }
}

@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class SupplierCreateDto {
  const SupplierCreateDto({
    required this.name,
    this.phone,
    this.email,
    this.address,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;

  Map<String, dynamic> toJson() => _$SupplierCreateDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class SupplierResponseDto {
  const SupplierResponseDto({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;

  factory SupplierResponseDto.fromJson(Map<String, dynamic> json) =>
      _$SupplierResponseDtoFromJson(json);
}
