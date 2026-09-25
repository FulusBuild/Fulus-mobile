import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/diagnostics/diagnostic_logger.dart';
import '../../../../core/diagnostics/models/diagnostic_enums.dart';
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

class CartCubit extends Cubit<CartState> {
  CartCubit({
    required DraftCartRepository draftCartRepository,
    required ProductRepository productRepository,
    required CustomerRepository customerRepository,
    required BusinessSettingsRepository businessSettingsRepository,
    required String locationId,
    DiagnosticLogger? diagnosticLogger,
  })  : _draftCartRepository = draftCartRepository,
        _productRepository = productRepository,
        _customerRepository = customerRepository,
        _businessSettingsRepository = businessSettingsRepository,
        _locationId = locationId,
        _diagnosticLogger = diagnosticLogger,
        super(const CartInitial()) {
    _init();
  }

  final DraftCartRepository _draftCartRepository;
  final ProductRepository _productRepository;
  final CustomerRepository _customerRepository;
  final BusinessSettingsRepository _businessSettingsRepository;
  final String _locationId;
  final DiagnosticLogger? _diagnosticLogger;

  /// Durable location context for this cubit. A CartCubit is never portable
  /// across locations; the Sell screen recreates it when the active context changes.
  String get locationId => _locationId;

  String? _draftCartId;

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
  Map<String, ProductWithStock> _catalogSnapshot = const {};
  bool _catalogLoaded = false;
  bool _submitting = false;
  bool _initializing = false;

  Future<void> _init() async {
    if (_initializing || isClosed) return;
    _initializing = true;
    _diagnosticLogger?.breadcrumb('Sell screen opened', category: DiagnosticCategory.sales);
    try {
      final draft = await _draftCartRepository.getOrCreateDraftCart(locationId: _locationId);
      if (isClosed) return;
      _draft = draft;
      _draftCartId = draft.localId;
      _resolvedCustomerId = draft.customerLocalId;
      if (draft.customerLocalId != null) {
        unawaited(_resolveCustomer(draft.customerLocalId));
      }

      await _cancelSubscriptions();
      _draftSub = _draftCartRepository.watchDraftCart(draft.localId).listen((updated) {
        if (updated == null) return;
        _draft = updated;
        if (updated.customerLocalId != _resolvedCustomerId) {
          unawaited(_resolveCustomer(updated.customerLocalId));
        }
        _applyTax();
        _emitLoaded();
      });
      _itemsSub = _draftCartRepository.watchItems(draft.localId).listen((items) {
        _items = items;
        _applyTax();
        _emitLoaded();
      });
      _paymentsSub = _draftCartRepository.watchPayments(draft.localId).listen((payments) {
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
        _catalogSnapshot = Map.unmodifiable(_catalog);
        _catalogLoaded = true;
        _emitLoaded();
      });

      _emitLoaded();
    } catch (e) {
      if (!isClosed) emit(CartFailure("Couldn't open the cart. ${e.toString()}"));
    } finally {
      _initializing = false;
    }
  }

  Future<void> retryInitialization() async {
    if (isClosed) return;
    await _cancelSubscriptions();
    _draft = null;
    _items = const [];
    _payments = const [];
    _customer = null;
    _resolvedCustomerId = null;
    _profile = null;
    _catalog
      ..clear();
    _catalogSnapshot = const {};
    _catalogLoaded = false;
    _emitInitial();
    await _init();
  }

  void _emitInitial() {
    if (!isClosed) emit(const CartInitial());
  }

  Future<void> _cancelSubscriptions() async {
    await _draftSub?.cancel();
    await _itemsSub?.cancel();
    await _paymentsSub?.cancel();
    await _settingsSub?.cancel();
    await _catalogSub?.cancel();
    _draftSub = null;
    _itemsSub = null;
    _paymentsSub = null;
    _settingsSub = null;
    _catalogSub = null;
  }

  Future<void> _resolveCustomer(String? customerLocalId) async {
    _resolvedCustomerId = customerLocalId;
    if (customerLocalId == null) {
      _customer = null;
      _emitLoaded();
      return;
    }
    final customer = await _customerRepository.getCustomerById(customerLocalId);
    if (_resolvedCustomerId == customerLocalId) {
      _customer = customer;
      _emitLoaded();
    }
  }

  double get _subtotal => _items.fold(0.0, (sum, i) => sum + i.lineTotal);

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
      catalog: _catalogSnapshot,
      catalogLoaded: _catalogLoaded,
      submitting: _submitting,
    ));
  }

  Future<void> addProduct(String productLocalId) => addProductQuantity(productLocalId, 1);

  Future<void> addProductQuantity(String productLocalId, int quantity) async {
    if (quantity <= 0) throw StateError('Enter a whole number greater than 0.');

    final current = state;
    if (current is! CartLoaded) return;
    final productWithStock = current.catalog[productLocalId];
    if (productWithStock == null || !productWithStock.product.isActive) {
      throw StateError('That product is no longer available.');
    }

    final existingLine = current.items.where((i) => i.productLocalId == productLocalId).toList();
    final existingQuantity = existingLine.fold<int>(0, (sum, i) => sum + i.quantity);
    final requestedTotal = existingQuantity + quantity;
    if (productWithStock.product.tracksStock && requestedTotal > productWithStock.currentStock) {
      throw StateError('Only ${productWithStock.currentStock} in stock.');
    }

    if (existingLine.isNotEmpty) {
      final line = existingLine.first;
      await _draftCartRepository.updateItemQuantity(
        itemLocalId: line.localId,
        quantity: line.quantity + quantity,
      );
    } else {
      await _draftCartRepository.addItem(
        draftCartLocalId: _draftCartId!,
        productLocalId: productLocalId,
        quantity: quantity,
        lineDiscount: 0.0,
      );
    }

    _diagnosticLogger?.breadcrumb(
      'Product added to cart',
      category: DiagnosticCategory.sales,
      data: {'Product ID': productLocalId, 'Quantity': '$quantity'},
    );
  }

  Future<void> addQuickSaleItem({required String description, required double unitPrice}) async {
    if (description.trim().isEmpty) throw StateError('Enter what you\'re selling.');
    if (unitPrice <= 0) throw StateError('Enter a price greater than 0.');
    await _draftCartRepository.addItem(draftCartLocalId: _draftCartId!, description: description.trim(), unitPrice: unitPrice, quantity: 1, lineDiscount: 0.0);
  }

  Future<void> incrementItem(DraftCartItem item) async {
    final current = state;
    if (current is! CartLoaded) return;
    if (item.productLocalId != null) {
      final productWithStock = current.catalog[item.productLocalId];
      if (productWithStock != null && productWithStock.product.tracksStock && item.quantity >= productWithStock.currentStock) {
        throw StateError('Only ${productWithStock.currentStock} in stock.');
      }
    }
    await _draftCartRepository.updateItemQuantity(itemLocalId: item.localId, quantity: item.quantity + 1);
    _diagnosticLogger?.breadcrumb('Cart quantity changed', category: DiagnosticCategory.sales);
  }

  Future<void> decrementItem(DraftCartItem item) async {
    if (item.quantity <= 1) {
      await removeItem(item.localId);
      return;
    }
    await _draftCartRepository.updateItemQuantity(itemLocalId: item.localId, quantity: item.quantity - 1);
    _diagnosticLogger?.breadcrumb('Cart quantity changed', category: DiagnosticCategory.sales);
  }

  Future<void> setItemQuantity(DraftCartItem item, int quantity) async {
    if (quantity <= 0) throw StateError('Enter a whole number greater than 0.');
    final current = state;
    if (current is CartLoaded && item.productLocalId != null) {
      final productWithStock = current.catalog[item.productLocalId];
      if (productWithStock != null && productWithStock.product.tracksStock && quantity > productWithStock.currentStock) {
        throw StateError('Only ${productWithStock.currentStock} in stock.');
      }
    }
    await _draftCartRepository.updateItemQuantity(itemLocalId: item.localId, quantity: quantity);
    _diagnosticLogger?.breadcrumb('Cart quantity changed', category: DiagnosticCategory.sales);
  }

  Future<void> removeItem(String itemLocalId) async {
    await _draftCartRepository.removeItem(itemLocalId);
    _diagnosticLogger?.breadcrumb('Item removed from cart', category: DiagnosticCategory.sales);
  }

  Future<void> updateItemDiscount(DraftCartItem item, double lineDiscount) async {
    if (lineDiscount < 0) throw StateError('Discount can\'t be negative.');
    if (lineDiscount > item.lineTotal) throw StateError('Discount can\'t be more than the line total.');
    await _draftCartRepository.updateItemDiscount(itemLocalId: item.localId, lineDiscount: lineDiscount);
  }

  Future<void> setWholeCartDiscount(double discount) async {
    final current = state;
    if (current is! CartLoaded) return;
    if (discount < 0) throw StateError('Discount can\'t be negative.');
    if (discount > current.subtotal) throw StateError('Discount can\'t be more than the subtotal.');
    await _draftCartRepository.setWholeCartDiscount(draftCartLocalId: current.draftCart.localId, discount: discount);
  }

  Future<void> restoreItem(DraftCartItem item) async {
    await _draftCartRepository.addItem(draftCartLocalId: _draftCartId!, productLocalId: item.productLocalId, description: item.productLocalId == null ? item.description : null, quantity: item.quantity, unitPrice: item.unitPrice, lineDiscount: item.lineDiscount);
  }

  Future<void> setCustomer(Customer? customer) async {
    _resolvedCustomerId = customer?.localId;
    _customer = customer;
    _emitLoaded();
    await _draftCartRepository.setCustomer(draftCartLocalId: _draftCartId!, customerLocalId: customer?.localId);
    _diagnosticLogger?.breadcrumb('Customer selected', category: DiagnosticCategory.sales);
  }

  Future<Customer> createAndSetWalkInCustomer(String name) async {
    if (name.trim().isEmpty) throw StateError('Enter a name.');
    final customer = await _customerRepository.createCustomer(CustomerDraft(name: name.trim()));
    await setCustomer(customer);
    return customer;
  }

  Future<void> addPayment(String method, double amount) async {
    const supportedMethods = {'cash', 'mobile_money', 'card', 'credit'};
    if (!supportedMethods.contains(method)) throw StateError('Choose a valid payment method.');
    if (amount <= 0) throw StateError('Enter an amount greater than 0.');
    final current = state;
    if (current is! CartLoaded) throw StateError('Cart is not ready yet.');
    final remaining = current.remaining;
    if (remaining <= 0.004) throw StateError('This sale is already fully paid.');
    if (method == 'credit' && current.customer == null) throw StateError('Select a customer before using credit.');
    if (method != 'cash' && amount > remaining + 0.004) throw StateError('That amount is more than the remaining balance.');
    await _draftCartRepository.addPayment(draftCartLocalId: _draftCartId!, method: method, amount: amount);
    _diagnosticLogger?.breadcrumb('Payment added', category: DiagnosticCategory.sales, data: {'Method': method});
  }

  Future<void> removePayment(String paymentLocalId) async {
    await _draftCartRepository.removePayment(paymentLocalId);
  }

  Future<Sale> completeSale() async {
    final current = state;
    if (current is! CartLoaded) throw StateError('Cart is not ready yet.');
    if (current.items.isEmpty) throw StateError('Add at least one item before completing the sale.');
    if (current.remaining > 0.004) throw StateError('Collect the remaining balance before completing the sale.');
    if (_submitting) throw StateError('Sale is already being completed.');
    _submitting = true;
    _emitLoaded();
    try {
      final sale = await _draftCartRepository.completeSale(_draftCartId!);
      return sale;
    } finally {
      _submitting = false;
      _emitLoaded();
    }
  }

  Future<void> clearCart() async {
    await _draftCartRepository.clearDraft(_draftCartId!);
  }

  @override
  Future<void> close() async {
    await _cancelSubscriptions();
    return super.close();
  }
}