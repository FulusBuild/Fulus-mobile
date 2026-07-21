import 'sale.dart';

/// The not-yet-persisted input to `SaleRepository.createSale` —
/// Architecture Section 4's exact example signature
/// (`createSale(SaleDraft draft)`). Everything a checkout flow has
/// decided BEFORE the sale has an identity of its own: which items,
/// which customer (if any), the location it happened at, and the
/// payment already taken. What it deliberately does NOT carry —
/// localId, clientReference, saleDate, createdAt, updatedAt — is
/// exactly the set of fields that only make sense once a real Sale is
/// being created, which [toSaleEntity] assigns at that exact moment.
///
/// `items` is `List<SaleItem>`, not a separate draft-item type,
/// deliberately matching Section 4's own sample
/// (`item.toDriftCompanion()` called directly on `draft.items`) — each
/// item is expected to already be a fully-formed domain SaleItem (with
/// its own localId) by the time checkout hands this off, since that's
/// the cart's responsibility (Section 2's cart Cubit — not yet built in
/// this phase), not something this type or the repository invents.
class SaleDraft {
  const SaleDraft({
    required this.items,
    required this.locationId,
    required this.amountPaid,
    this.customerId,
    this.discount = 0,
    this.tax = 0,
    this.paymentMethod,
    this.notes,
  });

  final List<SaleItem> items;

  /// Required, not optional — Architecture Section 7a: a sale always
  /// belongs to exactly one location, even for a single-location
  /// business, where the caller (checkout) resolves this silently to
  /// "the only location that exists" rather than the UI ever needing a
  /// picker for it.
  final String locationId;

  final String? customerId;
  final double discount;
  final double tax;
  final double amountPaid;
  final String? paymentMethod;
  final String? notes;

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get total => subtotal - discount + tax;

  /// Commits this draft into a real [Sale] — called exactly once, by
  /// the repository, at the moment persistence actually happens.
  /// [localId] and [clientReference] are supplied by the caller
  /// (Architecture Section 3: clientReference == localId, generated
  /// fresh via a ULID) rather than generated here, keeping "how IDs are
  /// generated" a single decision made in one place (the repository),
  /// not duplicated into this type too.
  Sale toSaleEntity({
    required String localId,
    required String clientReference,
  }) {
    final now = DateTime.now();
    return Sale(
      localId: localId,
      clientReference: clientReference,
      customerId: customerId,
      locationId: locationId,
      saleDate: now,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      amountPaid: amountPaid,
      paymentMethod: paymentMethod,
      notes: notes,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
  }
}
