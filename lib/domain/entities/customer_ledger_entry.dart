import 'package:json_annotation/json_annotation.dart';

part 'customer_ledger_entry.g.dart';

/// See tables.dart's `CustomerLedgerEntries` table doc comment for the
/// full sync-status analysis this entity's three entry types each have —
/// summarized on each enum value below, not repeated in full here.
enum CustomerLedgerEntryType {
  /// Written locally by the (not-yet-built, see this stage's own
  /// `NOTES.md`) Sales rework when a sale completes with `balanceDue >
  /// 0` for a selected customer — a local echo of a balance change the
  /// Sale row's own sync already accounts for server-side, not something
  /// with its own sync task.
  creditSale,

  /// Written by [CustomerCreditRepository.recordRepayment]. Has a real
  /// sync path ONLY when tied to a specific sale (`saleLocalId` set) —
  /// via updating that sale's own `amountPaid`, which needs Sales' own
  /// (not yet built) update-sale sync support to actually reach the
  /// server. A freestanding repayment (no `saleLocalId`) has no backend
  /// endpoint to reach at all today — confirmed by grepping the whole
  /// backend for a repayment/receive-money route and finding none.
  repayment,

  /// Written when a completed [Return]/refund (Sales, not yet built)
  /// reduces what a credit customer owes for reasons that aren't a
  /// repayment — no cash changed hands, goods came back instead.
  refundAdjustment;
}

class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.localId,
    this.serverId,
    required this.customerLocalId,
    required this.entryType,
    required this.amount,
    this.paymentMethod,
    this.note,
    this.saleLocalId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String localId;
  final String? serverId;
  final String customerLocalId;
  final CustomerLedgerEntryType entryType;

  /// Always the positive, raw amount involved — direction is implied by
  /// [entryType], not encoded as a signed number. For a [repayment] that
  /// exceeded the balance owed (Volume 7's own named failure scenario),
  /// this is the full amount actually tendered, not the smaller amount
  /// that was actually applied to the balance — see
  /// CustomerCreditRepository.recordRepayment's doc comment for where
  /// the excess is surfaced instead of silently dropped.
  final double amount;

  /// Backend precedent: `Sale.payment_method`/`Expense.payment_method`
  /// are both plain unconstrained strings, not an enum — matched here
  /// for the same reason.
  final String? paymentMethod;

  final String? note;

  /// See [CustomerLedgerEntryType.repayment]'s own doc comment for
  /// exactly what setting this does and doesn't currently do on the sync
  /// side.
  final String? saleLocalId;

  final DateTime createdAt;
  final DateTime updatedAt;
}

/// Not currently sent anywhere — kept ready for the day a sale-linked
/// repayment actually has a real endpoint to push to (see
/// [CustomerLedgerEntryType.repayment]'s doc comment). Modeled now,
/// alongside the entity, so that follow-up is a matter of writing the
/// API call, not designing the wire shape from scratch under time
/// pressure later.
@JsonSerializable(fieldRename: FieldRename.snake, createFromJson: false)
class RepaymentRequestDto {
  const RepaymentRequestDto({required this.amountPaid});

  /// Mirrors what `PATCH /api/sales/{id}` (`sale_service.update_sale`)
  /// actually accepts — the sale's new *total* amount paid, not a delta
  /// — verified directly against backend/app/schemas/sale.py's
  /// `SaleUpdate`.
  final double amountPaid;

  Map<String, dynamic> toJson() => _$RepaymentRequestDtoToJson(this);
}
