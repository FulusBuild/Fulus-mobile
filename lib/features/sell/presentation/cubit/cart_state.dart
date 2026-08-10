import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/draft_cart.dart';
import '../../../../domain/entities/product.dart';

/// State for `CartCubit` — mirrors the sealed-class-per-state pattern
/// `dashboard_summary.dart`'s `HomeHeroState` already established for
/// this codebase, rather than reaching for `freezed` (a pubspec
/// dependency, but not otherwise used anywhere in this tree yet — no
/// reason for the cart to be the first).
sealed class CartState {
  const CartState();
}

/// The draft cart is still being resolved — `getOrCreateDraftCart`
/// hasn't returned yet. Shown once, briefly, whenever Sell first opens
/// (Decision 14: it resolves to either a fresh cart or the one already
/// in progress).
final class CartInitial extends CartState {
  const CartInitial();
}

/// Opening or mutating the cart itself failed (not a normal empty-cart
/// or out-of-stock case — those stay inside [CartLoaded]). Distinct
/// from [CartInitial] so the Sell screen can show `FulusErrorState`
/// instead of a product grid over broken data.
final class CartFailure extends CartState {
  const CartFailure(this.message);
  final String message;
}

/// The live, editable cart. Every field here mirrors
/// `DraftCartRepository`'s own reactive streams plus the resolved
/// [Customer] and product catalog (with live stock) needed to render
/// and validate the Sell screen — this Cubit owns no cart data of its
/// own; the repository (and, beneath it, the DraftCarts table) remains
/// the actual source of truth, matching Decision 14's requirement that
/// the cart survive an app restart, not just a screen change.
final class CartLoaded extends CartState {
  const CartLoaded({
    required this.draftCart,
    required this.items,
    required this.payments,
    required this.customer,
    required this.locationId,
    required this.currencySymbol,
    required this.catalog,
    required this.catalogLoaded,
    required this.submitting,
  });

  final DraftCart draftCart;
  final List<DraftCartItem> items;
  final List<DraftCartPayment> payments;

  /// `null` means no customer attached — Volume 5: "Optional and
  /// skipped by default."
  final Customer? customer;

  final String locationId;
  final String currencySymbol;

  /// Every active product at [locationId], keyed by [Product.localId],
  /// with its current stock — the one place both the product grid and
  /// the cart's own quantity steppers read live stock from, so the two
  /// screens can never disagree about how much is left.
  final Map<String, ProductWithStock> catalog;

  /// False until the catalog stream's first event arrives — lets the
  /// product grid tell "still loading" apart from "genuinely empty
  /// catalog" (both start from an empty [catalog] map).
  final bool catalogLoaded;

  /// True while a payment is being recorded or the sale is being
  /// completed — the Payment screen's own loading state.
  final bool submitting;

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  /// Raw, pre-discount — mirrors `SaleDraft.subtotal`/`DraftCartItem.
  /// lineTotal`'s own convention exactly (see those getters' doc
  /// comments): a line's discount is never netted into its own total,
  /// so this sums the same raw figure `DraftCartRepositoryImpl.
  /// completeSale` does.
  double get subtotal => items.fold(0.0, (sum, i) => sum + i.lineTotal);

  double get total => subtotal - draftCart.wholeCartDiscount + draftCart.tax;

  double get amountPaid => payments.fold(0.0, (sum, p) => sum + p.amount);

  double get remaining => total - amountPaid;

  CartLoaded copyWith({
    DraftCart? draftCart,
    List<DraftCartItem>? items,
    List<DraftCartPayment>? payments,
    bool customerChanged = false,
    Customer? customer,
    String? currencySymbol,
    Map<String, ProductWithStock>? catalog,
    bool? catalogLoaded,
    bool? submitting,
  }) {
    return CartLoaded(
      draftCart: draftCart ?? this.draftCart,
      items: items ?? this.items,
      payments: payments ?? this.payments,
      customer: customerChanged ? customer : (customer ?? this.customer),
      locationId: locationId,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      catalog: catalog ?? this.catalog,
      catalogLoaded: catalogLoaded ?? this.catalogLoaded,
      submitting: submitting ?? this.submitting,
    );
  }
}
