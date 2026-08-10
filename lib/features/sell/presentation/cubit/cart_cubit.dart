import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/draft_cart.dart';
import '../../../../domain/entities/product.dart';
import '../../../../domain/entities/sale.dart';
import '../../../../domain/repositories/business_settings_repository.dart';
import '../../../../domain/repositories/customer_repository.dart';
import '../../../../domain/repositories/draft_cart_repository.dart';
import '../../../../domain/repositories/product_repository.dart';
import 'cart_state.dart';

/// The Sell screen's cart Cubit — pubspec.yaml's own dependency comment
/// names this exact file as flutter_bloc's one deliberate, narrow
/// exception to the app-wide Riverpod default (Architecture Section 2):
/// "a deliberate, narrow, justified exception... not the start of a
/// second state-management pattern elsewhere." `sale_draft.dart` and
/// `tables.dart` both point here as "Section 2's cart Cubit — not yet
/// built in this phase" before this pass.
///
/// Owns no cart data of its own — every mutation goes straight through
/// [DraftCartRepository], which is the actual source of truth (Decision
/// 14: the draft cart survives an app restart, not just a screen
/// change). This Cubit's job is combining that repository's three
/// separate streams (draft/items/payments) with a resolved [Customer],
/// the live product catalog (for stock-aware add/increment), and the
/// business's tax settings into one [CartState] the UI renders, and
/// translating simple UI actions (tap a product, +/-, swipe to remove,
/// pick a customer, take a payment) into the corresponding repository
/// calls — validation errors are thrown as [StateError] for the calling
/// widget to catch and show via `showFulusSnackbar`, the same
/// throws-on-bad-input convention [DraftCartRepository]'s own
/// implementation already uses.
///
/// One instance is created per Sell-tab session (see `sell_screen.dart`)
/// and lives for as long as that tab's navigation branch does — a sale
/// completing does not recreate it; `DraftCartRepositoryImpl.
/// completeSale` clears the same draft-cart row rather than deleting
/// it, so this Cubit's own subscriptions simply observe that row go
/// back to empty and the Sell screen is ready for the next sale with no
/// extra wiring.
class CartCubit extends Cubit<CartState> {
  CartCubit({
    required DraftCartRepository draftCartRepository,
    required ProductRepository productRepository,
    required CustomerRepository customerRepository,
    required BusinessSettingsRepository businessSettingsRepository,
    required String locationId,
  })  : _draftCartRepository = draftCartRepository,
        _productRepository = productRepository,
        _customerRepository = customerRepository,
        _businessSettingsRepository = businessSettingsRepository,
        _locationId = locationId,
        super(const CartInitial()) {
    _init();
  }

  final DraftCartRepository _draftCartRepository;
  final ProductRepository _productRepository;
  final CustomerRepository _customerRepository;
  final BusinessSettingsRepository _businessSettingsRepository;
  final String _locationId;

  late final String _draftCartId;

  StreamSubscription<DraftCart?>? _draftSub;
  StreamSubscription<List<DraftCartItem>>? _itemsSub;
  StreamSubscription<List<DraftCartPayment>>? _paymentsSub;
  StreamSubscription<BusinessProfile?>? _settingsSub;
  StreamSubscription<List<ProductWithStock>>? _catalogSub;

  DraftCart? _draft;
  List<DraftCartItem> _items = const [];
  List<DraftCartPayment> _payments = const [];
  Customer? _customer;
  String? _resolvedCustomerId;
  BusinessProfile? _profile;
  final Map<String, ProductWithStock> _catalog = {};
  bool _catalogLoaded = false;
  bool _submitting = false;

  Future<void> _init() async {
    try {
      final draft = await _draftCartRepository.getOrCreateDraftCart(locationId: _locationId);
      _draft = draft;
      _draftCartId = draft.localId;
      _resolvedCustomerId = draft.customerLocalId;
      if (draft.customerLocalId != null) {
        // Fire-and-forget — _emitLoaded() below already has enough to
        // show a first frame; the resolved name fills in the moment
        // this returns.
        unawaited(_resolveCustomer(draft.customerLocalId));
      }

      _draftSub = _draftCartRepository.watchDraftCart(_draftCartId).listen((updated) {
        if (updated == null) return;
        _draft = updated;
        if (updated.customerLocalId != _resolvedCustomerId) {
          unawaited(_resolveCustomer(updated.customerLocalId));
        }
        _applyTax();
        _emitLoaded();
      });
      _itemsSub = _draftCartRepository.watchItems(_draftCartId).listen((items) {
        _items = items;
        _applyTax();
        _emitLoaded();
      });
      _paymentsSub = _draftCartRepository.watchPayments(_draftCartId).listen((payments) {
        _payments = payments;
        _emitLoaded();
      });
      _settingsSub = _businessSettingsRepository.watchSettings().listen((profile) {
        _profile = profile;
        _applyTax();
        _emitLoaded();
      });
      _catalogSub = _productRepository.watchProducts(locationId: _locationId).listen((products) {
        _catalog
          ..clear()
          ..addEntries(products.map((p) => MapEntry(p.product.localId, p)));
        _catalogLoaded = true;
        _emitLoaded();
      });

      _emitLoaded();
    } catch (e) {
      if (!isClosed) emit(CartFailure("Couldn't open the cart. ${e.toString()}"));
    }
  }

  Future<void> _resolveCustomer(String? customerLocalId) async {
    _resolvedCustomerId = customerLocalId;
    if (customerLocalId == null) {
      _customer = null;
      _emitLoaded();
      return;
    }
    final customer = await _customerRepository.getCustomerById(customerLocalId);
    // Only apply if still current — a fast second change shouldn't be
    // clobbered by a slower earlier lookup's response arriving late.
    if (_resolvedCustomerId == customerLocalId) {
      _customer = customer;
      _emitLoaded();
    }
  }

  double get _subtotal => _items.fold(0.0, (sum, i) => sum + i.lineTotal);

  /// Volume 5, Checkout & Payment: "Tax is calculated automatically
  /// from the business-type default... always shown as its own visible
  /// line." [DraftCart.tax] exists precisely so a caller can supply
  /// this already-computed figure (see that field's own doc comment);
  /// this is that caller. Guarded against a redundant write so every
  /// item/settings change doesn't trigger a write-then-rewatch loop
  /// once the figure already matches.
  Future<void> _applyTax() async {
    final profile = _profile;
    final draft = _draft;
    if (profile == null || draft == null) return;
    final expectedTax = profile.vatEnabled ? _subtotal * (profile.vatRate / 100) : 0.0;
    if ((draft.tax - expectedTax).abs() < 0.005) return;
    await _draftCartRepository.setTax(draftCartLocalId: draft.localId, tax: expectedTax);
  }

  void _emitLoaded() {
    if (isClosed) return;
    final draft = _draft;
    if (draft == null) return;
    emit(CartLoaded(
      draftCart: draft,
      items: _items,
      payments: _payments,
      customer: _customer,
      locationId: _locationId,
      currencySymbol: _profile?.currencySymbol ?? '₦',
      catalog: Map.unmodifiable(_catalog),
      catalogLoaded: _catalogLoaded,
      submitting: _submitting,
    ));
  }

  // ---------------------------------------------------------------
  // Product selection / cart mutation
  // ---------------------------------------------------------------

  /// Adds one unit of the catalog product identified by
  /// [productLocalId] — merges into an existing line for the same
  /// product rather than creating a duplicate one, matching how a real
  /// till behaves when the same item is scanned/tapped twice. Throws
  /// [StateError] if the product can no longer be found, is inactive,
  /// or (when [Product.tracksStock] is on) already has every unit of
  /// live stock committed to this cart — task's "prevent selling more
  /// than available stock," enforced here rather than only by disabling
  /// the tile, so a fast double-tap can't race past a check the UI
  /// already ran once.
  Future<void> addProduct(String productLocalId) async {
    final current = state;
    if (current is! CartLoaded) return;
    final productWithStock = current.catalog[productLocalId];
    if (productWithStock == null || !productWithStock.product.isActive) {
      throw StateError('That product is no longer available.');
    }
    final alreadyInCart = current.items
        .where((i) => i.productLocalId == productLocalId)
        .fold<int>(0, (sum, i) => sum + i.quantity);
    if (productWithStock.product.tracksStock && alreadyInCart >= productWithStock.currentStock) {
      throw StateError('Only ${productWithStock.currentStock} in stock.');
    }
    final existingLine =
        current.items.where((i) => i.productLocalId == productLocalId).toList();
    if (existingLine.isNotEmpty) {
      final line = existingLine.first;
      await _draftCartRepository.updateItemQuantity(
        itemLocalId: line.localId,
        quantity: line.quantity + 1,
      );
    } else {
      await _draftCartRepository.addItem(
        draftCartLocalId: _draftCartId,
        productLocalId: productLocalId,
        quantity: 1,
        lineDiscount: 0.0,
      );
    }
  }

  /// Volume 5's Quick Sale — "for anything not in the catalog at all."
  Future<void> addQuickSaleItem({required String description, required double unitPrice}) async {
    if (description.trim().isEmpty) {
      throw StateError('Enter what you\'re selling.');
    }
    if (unitPrice <= 0) {
      throw StateError('Enter a price greater than 0.');
    }
    await _draftCartRepository.addItem(
      draftCartLocalId: _draftCartId,
      description: description.trim(),
      unitPrice: unitPrice,
      quantity: 1,
      lineDiscount: 0.0,
    );
  }

  Future<void> incrementItem(DraftCartItem item) async {
    final current = state;
    if (current is! CartLoaded) return;
    if (item.productLocalId != null) {
      final productWithStock = current.catalog[item.productLocalId];
      if (productWithStock != null &&
          productWithStock.product.tracksStock &&
          item.quantity >= productWithStock.currentStock) {
        throw StateError('Only ${productWithStock.currentStock} in stock.');
      }
    }
    await _draftCartRepository.updateItemQuantity(
      itemLocalId: item.localId,
      quantity: item.quantity + 1,
    );
  }

  Future<void> decrementItem(DraftCartItem item) async {
    if (item.quantity <= 1) {
      await removeItem(item.localId);
      return;
    }
    await _draftCartRepository.updateItemQuantity(
      itemLocalId: item.localId,
      quantity: item.quantity - 1,
    );
  }

  /// Backs the Bible's "tap-to-type entry for bulk amounts." Throws
  /// [StateError] for a non-positive quantity or one past live stock —
  /// task's "Invalid quantity" state is this throw, caught and shown by
  /// the calling dialog.
  Future<void> setItemQuantity(DraftCartItem item, int quantity) async {
    if (quantity <= 0) {
      throw StateError('Enter a whole number greater than 0.');
    }
    final current = state;
    if (current is CartLoaded && item.productLocalId != null) {
      final productWithStock = current.catalog[item.productLocalId];
      if (productWithStock != null &&
          productWithStock.product.tracksStock &&
          quantity > productWithStock.currentStock) {
        throw StateError('Only ${productWithStock.currentStock} in stock.');
      }
    }
    await _draftCartRepository.updateItemQuantity(itemLocalId: item.localId, quantity: quantity);
  }

  Future<void> removeItem(String itemLocalId) async {
    await _draftCartRepository.removeItem(itemLocalId);
  }

  /// Re-adds a just-removed line exactly as it was — the Bible's
  /// "Undo" toast after a swipe-to-remove. Preserves the original
  /// [DraftCartItem.unitPrice] explicitly (rather than letting
  /// [addProduct]/`addItem` re-resolve it from the product's current
  /// price) so an Undo can never silently change the price the cashier
  /// already saw.
  Future<void> restoreItem(DraftCartItem item) async {
    await _draftCartRepository.addItem(
      draftCartLocalId: _draftCartId,
      productLocalId: item.productLocalId,
      description: item.productLocalId == null ? item.description : null,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      lineDiscount: item.lineDiscount,
    );
  }

  // ---------------------------------------------------------------
  // Customer
  // ---------------------------------------------------------------

  Future<void> setCustomer(Customer? customer) async {
    _resolvedCustomerId = customer?.localId;
    _customer = customer;
    _emitLoaded();
    await _draftCartRepository.setCustomer(
      draftCartLocalId: _draftCartId,
      customerLocalId: customer?.localId,
    );
  }

  /// Volume 5: "a new customer can be added inline with just a name,
  /// without leaving Sell."
  Future<Customer> createAndSetWalkInCustomer(String name) async {
    if (name.trim().isEmpty) {
      throw StateError('Enter a name.');
    }
    final customer = await _customerRepository.createCustomer(CustomerDraft(name: name.trim()));
    await setCustomer(customer);
    return customer;
  }

  // ---------------------------------------------------------------
  // Payment / checkout
  // ---------------------------------------------------------------

  Future<void> addPayment(String method, double amount) async {
    if (amount <= 0) {
      throw StateError('Enter an amount greater than 0.');
    }
    await _draftCartRepository.addPayment(
      draftCartLocalId: _draftCartId,
      method: method,
      amount: amount,
    );
  }

  Future<void> removePayment(String paymentLocalId) async {
    await _draftCartRepository.removePayment(paymentLocalId);
  }

  /// The bridge to a real, synced [Sale] — see
  /// `DraftCartRepository.completeSale`'s own doc comment for what this
  /// aggregates. Leaves the draft cart untouched on failure (the
  /// repository only clears it after `SaleRepository.createSale`
  /// actually succeeds), so a failed sale never loses the cart — task's
  /// "Sale completion failure" state — and the caller can simply retry.
  Future<Sale> completeSale() async {
    if (state is! CartLoaded) {
      throw StateError('Cart is not ready yet.');
    }
    _submitting = true;
    _emitLoaded();
    try {
      final sale = await _draftCartRepository.completeSale(_draftCartId);
      return sale;
    } finally {
      _submitting = false;
      _emitLoaded();
    }
  }

  Future<void> clearCart() async {
    await _draftCartRepository.clearDraft(_draftCartId);
  }

  @override
  Future<void> close() {
    _draftSub?.cancel();
    _itemsSub?.cancel();
    _paymentsSub?.cancel();
    _settingsSub?.cancel();
    _catalogSub?.cancel();
    return super.close();
  }
}
