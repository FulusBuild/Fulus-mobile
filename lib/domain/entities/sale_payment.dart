/// One payment leg against a finished [Sale] — Volume 5's split-payment
import 'package:fulus_mobile/core/money/money.dart';
/// support. See tables.dart's `SalePayments` doc comment for the full
/// "no backend equivalent, rides with parent, aggregates into
/// Sale.paymentMethod/amountPaid" reasoning.
class SalePayment {
  const SalePayment({
    required this.localId,
    this.saleLocalId,
    required this.method,
    required this.amount,
    this.tenderedAmount,
    required this.recordedAt,
  });

  final String localId;

  /// Nullable — known when reading an existing row (`SalePaymentRowToDomain.
  /// toDomain()` always sets it), but not meaningfully available yet when
  /// constructing a fresh `SalePayment` before its real `Sale` exists
  /// (`DraftCartPayment.toSalePayment`, called before `createSale` has
  /// assigned an id) — same shape `SaleItem` avoided entirely by having
  /// no `saleLocalId` field at all; this one needs it for the read
  /// direction, so nullable rather than absent.
  final String? saleLocalId;

  final String method;
  @MoneyJsonConverter()
  final Money amount;

  /// For cash, the amount physically handed over. [amount] remains the
  /// amount applied to the sale. For non-cash legs this is null/equal to
  /// amount and therefore cannot create change.
  final Money? tenderedAmount;
  final DateTime recordedAt;
}
