import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/errors/module_failures.dart';
import '../../domain/entities/receipt.dart';
import '../../domain/repositories/receipt_repository.dart';
import '../../domain/usecases/receipt_engine.dart';
import '../local/database/database.dart';

/// INTEGRATION NOTE — read before touching this file: this is the one
/// place in Stage 9 that reads Sale/SaleItem/Product/Customer/
/// BusinessSettings columns directly, because ReceiptData and
/// ReceiptEngine (both schema-agnostic by design — see receipt.dart's
/// own doc comment) need concrete values from somewhere. Column names
/// below were verified against the merged Sales/SaleItems/Products/
/// Customers/BusinessSettings/Users tables directly (Phase 0 completion
/// pass) — if a future schema change removes or renames one of these,
/// this is the only file that needs adjusting; ReceiptData and
/// ReceiptEngine do not.
///
/// One thing worth flagging for whoever next touches this: `paymentStatus`
/// is computed here from amountPaid vs total (see [_derivePaymentStatus])
/// rather than read from a stored column, because Sales has no such
/// column — matching the backend's own Sale.balance_due/payment_status,
/// both Python @property values, not mapped_columns (verified directly
/// during the original audit). This is correct as-is, not a gap.
class ReceiptRepositoryImpl implements ReceiptRepository {
  ReceiptRepositoryImpl({
    required AppDatabase db,
    ReceiptEngine engine = const ReceiptEngine(),
  })  : _db = db,
        _engine = engine;

  final AppDatabase _db;
  final ReceiptEngine _engine;

  @override
  Future<ReceiptData> buildReceiptData(String saleId) async {
    final sale = await (_db.select(_db.sales)..where((s) => s.localId.equals(saleId))).getSingleOrNull();
    if (sale == null) {
      throw ReceiptDataUnavailable(saleId);
    }

    final itemRows = await (_db.select(_db.saleItems)..where((i) => i.saleLocalId.equals(saleId))).get();
    final items = <ReceiptLineItem>[];
    for (final item in itemRows) {
      final productLocalId = item.productLocalId;
      final product = productLocalId == null
          ? null
          : await (_db.select(_db.products)..where((pr) => pr.localId.equals(productLocalId)))
              .getSingleOrNull();
      items.add(ReceiptLineItem(
        productName: product?.name ?? item.description,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        lineTotal: item.unitPrice * item.quantity,
      ));
    }

    final settings = await (_db.select(_db.businessSettings)..where((b) => b.id.equals('singleton'))).getSingleOrNull();

    String? customerName, customerPhone, customerEmail, customerAddress;
    final customerId = sale.customerId;
    if (customerId != null) {
      final customer =
          await (_db.select(_db.customers)..where((c) => c.localId.equals(customerId))).getSingleOrNull();
      customerName = customer?.name;
      customerPhone = customer?.phone;
      customerEmail = customer?.email;
      customerAddress = customer?.address;
    }

    // Real now — Sales.cashierUserId (schema v4) plus a Users lookup.
    // Still legitimately null for a sale made before this column
    // existed, or one with nobody signed in when it was made; either
    // way the receipt just omits the line, which ReceiptEngine already
    // handles (cashierName has always been nullable on ReceiptData).
    String? cashierName;
    final cashierUserId = sale.cashierUserId;
    if (cashierUserId != null) {
      final cashier =
          await (_db.select(_db.users)..where((u) => u.localId.equals(cashierUserId))).getSingleOrNull();
      cashierName = cashier?.fullName;
    }

    final notes = (sale.notes != null && sale.notes!.startsWith('[CANCELLED')) ? null : sale.notes;

    // Feature: split-payment receipt breakdown — see
    // ReceiptData.paymentBreakdown's own doc comment. Queried directly
    // (this method already works with raw DB rows throughout, not
    // domain entities) rather than through SaleRepository, matching
    // this class's existing style.
    List<({String method, double amount})>? paymentBreakdown;
    if (sale.paymentMethod == 'split') {
      final legs = await (_db.select(_db.salePayments)..where((p) => p.saleLocalId.equals(saleId))).get();
      if (legs.isNotEmpty) {
        paymentBreakdown = [for (final leg in legs) (method: _displayPaymentMethod(leg.method), amount: leg.amount)];
      }
    }

    return ReceiptData(
      businessName: settings?.businessName ?? 'Business',
      businessAddress: settings?.address,
      businessPhone: settings?.phone,
      businessTin: settings?.tin,
      vatEnabled: settings?.vatEnabled ?? false,
      vatRate: settings?.vatRate ?? 7.5,
      cashierName: cashierName,
      invoiceNumber: sale.invoiceNumber ?? sale.localId,
      saleDate: sale.saleDate,
      items: items,
      subtotal: sale.subtotal,
      discount: sale.discount,
      tax: sale.tax,
      total: sale.total,
      amountPaid: sale.amountPaid,
      paymentStatus: _derivePaymentStatus(sale.notes, sale.amountPaid, sale.total),
      paymentMethod: sale.paymentMethod,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      notes: notes,
      receiptFooter: settings?.receiptFooter,
      currencySymbol: settings?.currencySymbol ?? '₦',
      paymentBreakdown: paymentBreakdown,
    );
  }

  /// See class doc point 1 above for why this exists instead of reading
  /// a stored column.
  String _derivePaymentStatus(String? notes, double amountPaid, double total) {
    if (notes != null && notes.startsWith('[CANCELLED')) return 'cancelled';
    if (amountPaid <= 0) return 'unpaid';
    if (amountPaid >= total) return 'paid';
    return 'partial';
  }

  @override
  GeneratedReceipt renderThermal(ReceiptData data) => _engine.renderThermal(data);

  @override
  Future<GeneratedReceipt> renderPdf(ReceiptData data) => _engine.renderPdf(data);

  @override
  Future<String> writeToTempFile(GeneratedReceipt receipt) async {
    final cacheDir = await getTemporaryDirectory();
    final receiptsDir = Directory(p.join(cacheDir.path, 'receipts'));
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    final path = p.join(receiptsDir.path, receipt.suggestedFileName);
    await File(path).writeAsBytes(receipt.bytes, flush: true);
    return path;
  }

  /// Same mapping as `RealMoneyRepositoryImpl._displayPaymentMethod`
  /// (features/money/data/real_money_repository.dart) — kept as its own
  /// small local copy rather than a shared import across those two
  /// layers, but deliberately identical output, so a payment method
  /// reads the same on the Money screen and on the receipt it came
  /// from.
  String _displayPaymentMethod(String storageKey) {
    switch (storageKey) {
      case 'cash':
        return 'Cash';
      case 'mobile_money':
        return 'Mobile Money';
      case 'card':
        return 'Card';
      case 'credit':
        return 'Credit';
      default:
        return storageKey
            .split('_')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    }
  }
}
