import '../../data/local/database/database.dart';
import '../../data/remote/endpoints/sales_api.dart';
import '../../domain/entities/sale.dart';
import '../../domain/repositories/sale_repository.dart';
import '../sync_handler.dart';

/// The only SyncHandler that exists in this checkpoint — matches the
/// only SyncTask factory that exists (SyncTask.createSale) and the only
/// repository built so far (SaleRepository). Registered into SyncEngine
/// under entityType 'sale' in bootstrap.dart.
class SaleSyncHandler implements SyncHandler {
  SaleSyncHandler({
    required AppDatabase db,
    required SalesApi salesApi,
    required SaleRepository saleRepository,
  })  : _db = db,
        _salesApi = salesApi,
        _saleRepository = saleRepository;

  final AppDatabase _db;
  final SalesApi _salesApi;
  final SaleRepository _saleRepository;

  @override
  Future<void> sync(SyncQueueItem item) async {
    if (item.operation != 'create') {
      // No caller in this codebase enqueues 'update'/'delete' for
      // 'sale' today — SyncTask.createSale is the only factory that
      // exists. Kept as an explicit, honest failure rather than
      // silently doing nothing if this is ever somehow reached.
      throw StateError(
        'SaleSyncHandler does not support operation "${item.operation}" '
        'yet — only "create" is implemented.',
      );
    }

    final sale = await _saleRepository.getSaleByLocalId(item.entityLocalId);
    if (sale == null) {
      throw StateError(
        'No local sale found for ${item.entityLocalId} — the queue item '
        'outlived its own row.',
      );
    }

    final dto = await _buildCreateDto(sale);

    final response = await _salesApi.createSale(
      dto: dto,
      locationLocalId: sale.locationId,
    );

    // response.serverId and .invoiceNumber are non-null in practice —
    // SalesApi's own _toDomain always populates both directly from a
    // real server response (verified directly in sales_api.dart) — the
    // `!` here reflects that guarantee, not an unchecked assumption.
    await _saleRepository.markSynced(
      localId: sale.localId,
      serverId: response.serverId!,
      invoiceNumber: response.invoiceNumber!,
    );
  }

  /// Builds the wire-format DTO from the local Sale — and this is
  /// where a real, currently-unresolved gap surfaces: SaleItemCreateDto
  /// needs each product's SERVER id (backend/app/schemas/sale.py's
  /// SaleItemCreate.product_id), not its local ULID, and SaleCreateDto
  /// needs the customer's server id the same way. Neither Product nor
  /// Customer has its own repository or serverId-reconciliation built
  /// yet in this phase (Architecture Section 4: "one repository
  /// interface per domain concept" — only SaleRepository exists so
  /// far) — there is currently no mechanism by which a product or
  /// customer row would even HAVE a serverId populated, since neither
  /// is created or pulled-down through the mobile app yet.
  ///
  /// Rather than silently sending the local ULID as if it were a
  /// server id (which would either 422 confusingly or, worse, silently
  /// corrupt data if the backend ever happened to accept an arbitrary
  /// string there), this throws a clear, specific error naming exactly
  /// which product/customer is missing a serverId. SyncEngine's
  /// catch-all treats this the same as a network failure (retry-
  /// eligible, counts toward the attempts threshold) — a deliberate
  /// choice, not an oversight: the gap is real but temporary (it
  /// disappears once Product/Customer sync exists), so treating it as
  /// "try again later" rather than an immediate, permanent
  /// attentionNeeded is the more honest framing of what's actually
  /// going on, even though today nothing will make it succeed sooner.
  Future<SaleCreateDto> _buildCreateDto(Sale sale) async {
    String? customerServerId;
    if (sale.customerId != null) {
      final customer = await (_db.select(_db.customers)
            ..where((c) => c.localId.equals(sale.customerId!)))
          .getSingleOrNull();
      customerServerId = customer?.serverId;
      if (customerServerId == null) {
        throw StateError(
          'Customer ${sale.customerId} has no serverId yet — customer '
          'sync is not built in this phase, so this sale cannot be '
          'created server-side until that exists.',
        );
      }
    }

    final items = <SaleItemCreateDto>[];
    for (final item in sale.items) {
      final productLocalId = item.productLocalId;
      if (productLocalId == null) {
        throw StateError(
          'Sale item has no productLocalId (a Quick Sale line) — this '
          'sale should have been marked attentionNeeded at creation '
          'instead of reaching sync.',
        );
      }
      final product = await (_db.select(_db.products)
            ..where((p) => p.localId.equals(productLocalId)))
          .getSingleOrNull();
      final productServerId = product?.serverId;
      if (productServerId == null) {
        throw StateError(
          'Product $productLocalId has no serverId yet — product '
          'sync is not built in this phase, so this sale cannot be '
          'created server-side until that exists.',
        );
      }
      items.add(SaleItemCreateDto(
        productId: productServerId,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
      ));
    }

    return SaleCreateDto(
      items: items,
      customerId: customerServerId,
      locationId: sale.locationId,
      discount: sale.discount,
      tax: sale.tax,
      amountPaid: sale.amountPaid,
      paymentMethod: sale.paymentMethod,
      notes: sale.notes,
      clientReference: sale.clientReference,
      saleDate: sale.saleDate,
    );
  }
}
