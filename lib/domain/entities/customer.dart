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
  });

  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;

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

/// POST /api/customers's response — mirrors CustomerOut exactly.
/// duplicate_warning is deliberately NOT modeled here: it's a one-time,
/// creation-response-only signal with no local storage or reconciliation
/// role (verified directly: CustomerOut's own docstring confirms it's
/// never populated on any other response), and this checkpoint has no
/// UI yet to surface it to a cashier — a real, honest gap for whoever
/// builds that screen, not something to silently drop without noting.
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
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double outstandingBalance;

  factory CustomerResponseDto.fromJson(Map<String, dynamic> json) =>
      _$CustomerResponseDtoFromJson(json);
}
