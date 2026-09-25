import '../entities/return_request.dart';

/// The real refund/return mechanism — see tables.dart's `ReturnRequests`
/// doc comment for the full context (`pos_service.py`'s
/// `create_return`/`approve_return`/`complete_return`).
abstract class ReturnRepository {
  /// Mirrors `pos_service.get_return_eligibility` — "so the UI can
  /// show/limit the right amount before the cashier tries to submit a
  /// return, instead of only finding out via a rejected request."
  Future<List<ReturnEligibilityLine>> getReturnEligibility(
    String originalSaleLocalId,
  );

  /// [autoApprove] mirrors the backend's `requester.role in (MANAGER,
  /// ADMIN)` check — computed by the *caller*, not this method: the
  /// role/permission decision belongs to the Auth/Employee stage, the
  /// same "mechanics here, permission decision elsewhere" split every
  /// other approval-gated write in this codebase follows. Pass `true`
  /// for an owner/manager raising their own return, `false` for an
  /// employee whose return needs approval first.
  ///
  /// Validates every requested item against the same eligibility logic
  /// [getReturnEligibility] exposes, and computes `ReturnRequest.
  /// refundAmount` from each product's weighted-average price within
  /// the original sale.
  Future<ReturnRequest> createReturn({
    required String originalSaleLocalId,
    required List<ReturnItemRequest> items,
    required String returnReason,
    required String refundMethod,
    required bool autoApprove,
    bool isVoid = false,
  });

  /// A cashier/owner correcting their own mistake, not a customer
  /// return — reuses createReturn/completeReturn for every line still
  /// eligible on the sale (typically all of it, for a sale voided
  /// right after ringing it up), auto-approved and completed in one
  /// call rather than left pending. [refundMethod] isn't asked for:
  /// it's set to the original sale's own payment method, since a void
  /// doesn't introduce a new refund channel — it just undoes one that
  /// never should have happened. Throws if the sale has already been
  /// fully refunded/voided (nothing left eligible to void).
  Future<ReturnRequest> voidSale({
    required String saleLocalId,
    required String reason,
  });

  /// Throws if the return isn't currently `pending` — mirrors
  /// `approve_return`'s own guard.
  Future<ReturnRequest> approveOrRejectReturn({
    required String returnLocalId,
    required bool approve,
  });

  /// Restores stock for every line and, when the original sale had a
  /// customer and was sold on credit, reduces what they owe. Throws if
  /// the return isn't currently `approved`.
  Future<ReturnRequest> completeReturn(String returnLocalId);

  Future<ReturnRequest?> getReturnById(String localId);

  /// [isVoid], when non-null, additionally filters to only voids
  /// (`true`) or only genuine customer returns (`false`) — for report
  /// views that need to tell the two apart.
  Stream<List<ReturnRequest>> watchReturns({ReturnStatus? status, bool? isVoid});

  /// Reconciles a locally-created return with the server's own identity
  /// once the sync handler successfully pushes it — same role as every
  /// other markSynced in this codebase.
  Future<void> markSynced({required String localId, required String serverId, String? operationId});
}
