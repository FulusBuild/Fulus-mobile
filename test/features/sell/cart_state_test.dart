import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/domain/entities/draft_cart.dart';
import 'package:fulus_mobile/features/sell/presentation/cubit/cart_state.dart';

/// Regression coverage for a confirmed business-logic bug found during
/// audit: `CartLoaded.total` used to be `subtotal -
/// draftCart.wholeCartDiscount + draftCart.tax`, which silently ignored
/// every line's own `lineDiscount` — while the actual persisted sale
/// (`DraftCartRepositoryImpl.completeSale`, via `SaleDraft.total`)
/// always correctly combined whole-cart AND line discounts. There was
/// no UI path to set either kind of discount from Sell at the time this
/// was found, so the bug was dormant rather than live — this file pins
/// the correct formula down before any such UI is built on top of it.
void main() {
  DraftCart draftCartWith({
    double wholeCartDiscount = 0.0,
    double tax = 0.0,
  }) {
    final now = DateTime.now();
    return DraftCart(
      localId: 'draft-1',
      locationId: 'loc-1',
      wholeCartDiscount: wholeCartDiscount,
      tax: tax,
      createdAt: now,
      updatedAt: now,
    );
  }

  DraftCartItem itemWith({
    required String localId,
    required int quantity,
    required double unitPrice,
    double lineDiscount = 0.0,
  }) {
    return DraftCartItem(
      localId: localId,
      draftCartLocalId: 'draft-1',
      productLocalId: 'prod-1',
      quantity: quantity,
      unitPrice: unitPrice,
      lineDiscount: lineDiscount,
    );
  }

  CartLoaded loadedWith({
    required DraftCart draftCart,
    required List<DraftCartItem> items,
    List<DraftCartPayment> payments = const [],
  }) {
    return CartLoaded(
      draftCart: draftCart,
      items: items,
      payments: payments,
      customer: null,
      locationId: 'loc-1',
      currencySymbol: '₦',
      catalog: const {},
      catalogLoaded: true,
      submitting: false,
    );
  }

  group('CartLoaded.total', () {
    test('with no discounts at all, total is just subtotal plus tax', () {
      final state = loadedWith(
        draftCart: draftCartWith(tax: 50),
        items: [itemWith(localId: 'i1', quantity: 2, unitPrice: 500)],
      );

      expect(state.subtotal, 1000);
      expect(state.total, 1050);
    });

    test('a whole-cart-only discount is subtracted correctly '
        '(pre-existing behavior, still correct)', () {
      final state = loadedWith(
        draftCart: draftCartWith(wholeCartDiscount: 100, tax: 0),
        items: [itemWith(localId: 'i1', quantity: 3, unitPrice: 1500)],
      );

      expect(state.subtotal, 4500);
      expect(state.total, 4400);
    });

    test(
        'a per-line-only discount is subtracted from total — the exact '
        'bug: this used to be silently ignored', () {
      final state = loadedWith(
        draftCart: draftCartWith(),
        items: [
          itemWith(localId: 'i1', quantity: 1, unitPrice: 1000, lineDiscount: 150),
        ],
      );

      expect(state.subtotal, 1000);
      // Before the fix this returned 1000 (wholeCartDiscount was 0, so
      // nothing was ever subtracted) — the exact defect this pins down.
      expect(state.total, 850);
    });

    test('whole-cart and multiple line discounts combine additively, '
        'matching combineDiscount / completeSale exactly', () {
      final state = loadedWith(
        draftCart: draftCartWith(wholeCartDiscount: 200, tax: 75),
        items: [
          itemWith(localId: 'i1', quantity: 1, unitPrice: 1000, lineDiscount: 50),
          itemWith(localId: 'i2', quantity: 2, unitPrice: 750, lineDiscount: 25),
        ],
      );

      // subtotal = 1000 + 1500 = 2500
      // discount = 200 (whole-cart) + 50 + 25 (lines) = 275
      // total = 2500 - 275 + 75 (tax) = 2300
      expect(state.subtotal, 2500);
      expect(state.discount, 275);
      expect(state.total, 2300);
    });

    test('remaining reflects the corrected total, not just what payments '
        'cover against an under-counted total', () {
      final state = loadedWith(
        draftCart: draftCartWith(),
        items: [
          itemWith(localId: 'i1', quantity: 1, unitPrice: 1000, lineDiscount: 150),
        ],
        payments: const [],
      );

      expect(state.total, 850);
      expect(state.remaining, 850);
    });

    test('a 100% line discount reduces that line\'s contribution to zero',
        () {
      final state = loadedWith(
        draftCart: draftCartWith(),
        items: [
          itemWith(localId: 'i1', quantity: 2, unitPrice: 500, lineDiscount: 1000),
        ],
      );

      expect(state.subtotal, 1000);
      expect(state.total, 0);
    });
  });
}
