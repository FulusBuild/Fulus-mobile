import 'package:json_annotation/json_annotation.dart';

part 'customer.g.dart';

/// Mirrors the Customers table exactly — business-wide per Architecture
/// Section 7a's explicit carve-out ("a customer's identity, credit
/// balance, and purchase history belong to the whole business"), no
/// locationId.
class Customer {
  const Customer({
    required this.localId,
    this.serverId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.outstandingBalance,
    this.creditLimit,
    required this.purchaseCount,
    this.loyaltyThreshold,
    this.photoPath,
    this.duplicateWarning,
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
  final String? notes;
  final double outstandingBalance;

  /// **Bible-only** (Product Design Bible Volume 7: "Credit limit —
  /// No [required] — A guide, not an automatic block — see Decision
  /// 23"). No backend column — confirmed directly against
  /// backend/app/models/customer.py, same audit as Product's
  /// tracksStock. Never enforced as a hard block anywhere this is read.
  final double? creditLimit;

  /// **Bible-only** (Volume 7 Loyalty section: "a purchase count per
  /// customer"). No backend column. Incremented locally when a sale
  /// completes for this customer — genuinely local-only, same status as
  /// [CustomerLedgerEntry]'s `creditSale` rows: an honest local echo of
  /// something the backend doesn't track server-side at all today, not
  /// a value with anywhere to sync.
  final int purchaseCount;

  /// **Bible-only** (Volume 7: "an optional owner-set threshold, e.g.
  /// every 10th purchase"). `null` means loyalty is off, not zero.
  final int? loyaltyThreshold;

  /// **Bible-only** (Volume 7: "Photo — No [required] — Helps a cashier
  /// recognize regulars visually"). Same local-file-path, no-backend-
  /// column status as Product.photoPath.
  final String? photoPath;

  /// Backed by the `lastSyncWarning` column (tables.dart) — set once by
  /// markSynced if a create response carried `duplicate_warning`, read
  /// back here on every later load of this row. See that column's own
  /// doc comment for the full trail: persisted and queryable, but
  /// nothing in this pass builds a UI that actually surfaces it.
  final String? duplicateWarning;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// The wire-format request, using [clientReference] (in practice
  /// always this same Customer's own localId — see
  /// CustomerSyncHandler's call site) for the same idempotency reasoning
  /// as Sale (Architecture Section 3): a retried sync submission is safe
  /// to resend rather than a risk of creating a duplicate customer
  /// (backend/app/models/customer.py's client_reference column,
  /// migration 0012_customer_client_reference, added specifically to
  /// close this gap — customer creation had no idempotency protection
  /// at all before that). Lives here, not on CustomerDraft, because it
  /// needs to be callable at SYNC time, once only a persisted Customer
  /// exists — the original draft is long gone by then.
  CustomerCreateDto toCreateDto({required String clientReference}) {
    return CustomerCreateDto(
      name: name,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
      clientReference: clientReference,
    );
  }
}

/// The not-yet-persisted input to CustomerRepository.createCustomer —
/// the common "new walk-in customer added at checkout" POS flow, same
/// shape of split SaleDraft/Sale already established: everything a
/// cashier has entered, minus the identity fields (localId,
/// createdAt/updatedAt) only assigned at the moment of creation.
class CustomerDraft {
  const CustomerDraft({
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.creditLimit,
    this.loyaltyThreshold,
    this.photoPath,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double? creditLimit;
  final int? loyaltyThreshold;
  final String? photoPath;

  Customer toCustomerEntity({required String localId}) {
    final now = DateTime.now();
    return Customer(
      localId: localId,
      name: name,
      phone: phone,
      email: email,
      address: address,
      notes: notes,
      outstandingBalance: 0,
      creditLimit: creditLimit,
      purchaseCount: 0,
      loyaltyThreshold: loyaltyThreshold,
      photoPath: photoPath,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// POST /api/customers's body — request-only, mirrors CustomerCreate
/// exactly (backend/app/schemas/customer.py, verified directly,
/// including client_reference from migration
/// 0012_customer_client_reference).
@JsonSerializable(fieldRename: FieldRename.snake, createFactory: false)
class CustomerCreateDto {
  const CustomerCreateDto({
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.clientReference,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final String? clientReference;

  Map<String, dynamic> toJson() => _$CustomerCreateDtoToJson(this);
}

/// POST /api/customers's response — mirrors CustomerOut exactly,
/// including `duplicate_warning` (verified directly against
/// backend/app/schemas/customer.py: `duplicate_warning: str | None =
/// None`, populated by customer_service.create_customer when the new
/// customer's phone or email matched an existing active customer —
/// creates it anyway, just flags it). Wired through to
/// CustomerSyncHandler → CustomerRepositoryImpl.markSynced below, which
/// is as far as the data layer can take it — nothing in this pass
/// builds a UI to actually show a cashier this warning; that's a real,
/// separate, still-open task, not something this fix silently finishes.
@JsonSerializable(fieldRename: FieldRename.snake, createToJson: false)
class CustomerResponseDto {
  const CustomerResponseDto({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.outstandingBalance,
    this.duplicateWarning,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double outstandingBalance;
  final String? duplicateWarning;

  factory CustomerResponseDto.fromJson(Map<String, dynamic> json) =>
      _$CustomerResponseDtoFromJson(json);
}
