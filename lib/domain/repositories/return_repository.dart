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

  Stream<List<ReturnRequest>> watchReturns({ReturnStatus? status});

  /// Reconciles a locally-created return with the server's own identity
  /// once the sync handler successfully pushes it — same role as every
  /// other markSynced in this codebase.
  Future<void> markSynced({required String localId, required String serverId});
}
