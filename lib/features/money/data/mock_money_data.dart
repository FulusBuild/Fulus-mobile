import 'dart:math';

import '../domain/money_transaction.dart';

/// A deterministic ~120 days of realistic small-business activity —
/// see `money_repository.dart`'s doc comment for why this feature is
/// mock-backed at all. Deterministic (seeded [Random]) so the same
/// history renders every app launch rather than reshuffling underneath
/// a reviewer between screens.
///
/// Generated once and shared by every [MockMoneyRepository] method —
/// the summary cards, the breakdown lists, and the transaction feed all
/// read from this exact same list, filtered differently, which is what
/// keeps the numbers reconciling across the Cash Flow screen (Volume 8
/// is explicit that Money In/Out is "one view," not five screens that
/// could each tell a slightly different story).
List<MoneyTransaction> generateMockMoneyTransactions({int days = 120}) {
  final random = Random(20260810);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final transactions = <MoneyTransaction>[];
  var invoiceNumber = 1000 + random.nextInt(200);
  var idCounter = 0;
  String nextId() => 'txn-${(++idCounter).toString().padLeft(5, '0')}';

  const customerNames = [
    'Fatima Ibrahim',
    'Chidi Nwosu',
    'Amaka Okoro',
    'Tunde Bakare',
    'Blessing Eze',
    'Aisha Bello',
  ];
  const supplierNames = ['Ngozi Books & Stationery', 'Alaba Wholesale Traders', 'Kano Foodstuff Depot'];
  const products = [
    'Bag of Rice (5kg)',
    'Vegetable Oil (1L)',
    'Bar Soap',
    'Phone Credit (₦1,000)',
    'Bottled Water (Carton)',
    'Detergent (1kg)',
    'Exercise Book (Pack)',
    'Batteries (Pack)',
    'Sachet Milk (Carton)',
    'Biscuits (Carton)',
  ];
  const paymentMethods = ['Cash', 'Mobile Money', 'Bank Transfer', 'Card'];
  const paymentWeights = [0.45, 0.30, 0.15, 0.10];

  String weightedPaymentMethod() {
    final roll = random.nextDouble();
    var cumulative = 0.0;
    for (var i = 0; i < paymentMethods.length; i++) {
      cumulative += paymentWeights[i];
      if (roll <= cumulative) return paymentMethods[i];
    }
    return paymentMethods.first;
  }

  double roundToNaira(double value) => value.roundToDouble();

  for (var dayOffset = days - 1; dayOffset >= 0; dayOffset--) {
    final day = today.subtract(Duration(days: dayOffset));
    final isFirstOfMonth = day.day == 1;
    final isMidMonth = day.day == 15;

    // ── Sales income: 0-5 a day, most days land in the middle. ────────
    final saleCount = min(5, max(0, (random.nextDouble() * 5).round() - (day.weekday == DateTime.sunday ? 1 : 0)));
    for (var s = 0; s < saleCount; s++) {
      final itemCount = 1 + random.nextInt(4);
      final lineItems = <String>[];
      var total = 0.0;
      for (var i = 0; i < itemCount; i++) {
        final product = products[random.nextInt(products.length)];
        final qty = 1 + random.nextInt(3);
        final unitPrice = roundToNaira(300 + random.nextDouble() * 4200);
        final lineTotal = unitPrice * qty;
        total += lineTotal;
        lineItems.add('$qty × $product — ₦${lineTotal.toStringAsFixed(0)}');
      }
      final hasCustomer = random.nextDouble() < 0.3;
      final customer = hasCustomer ? customerNames[random.nextInt(customerNames.length)] : 'Walk-in customer';
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.saleIncome,
        title: 'Sale — INV-${invoiceNumber++}',
        subtitle: customer,
        amount: roundToNaira(total),
        dateTime: day.add(Duration(hours: 8 + random.nextInt(11), minutes: random.nextInt(60))),
        paymentMethod: weightedPaymentMethod(),
        counterpartyName: customer,
        reference: 'INV-${invoiceNumber - 1}',
        lineItems: lineItems,
      ));
    }

    // ── Manual income: occasional. ─────────────────────────────────────
    if (random.nextDouble() < 0.08) {
      const sources = ['Old shelf sold', 'Space rental income', 'Refund from supplier', 'Scrap sale'];
      final source = sources[random.nextInt(sources.length)];
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.manualIncome,
        title: source,
        subtitle: 'Other income',
        amount: roundToNaira(2000 + random.nextDouble() * 18000),
        dateTime: day.add(Duration(hours: 9 + random.nextInt(9))),
        paymentMethod: weightedPaymentMethod(),
      ));
    }

    // ── Customer repayments: occasional. ───────────────────────────────
    if (random.nextDouble() < 0.16) {
      final customer = customerNames[random.nextInt(customerNames.length)];
      final method = random.nextDouble() < 0.6 ? 'Cash' : 'Mobile Money';
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.customerRepayment,
        title: 'Repayment — $customer',
        subtitle: method,
        amount: roundToNaira(2000 + random.nextDouble() * 13000),
        dateTime: day.add(Duration(hours: 10 + random.nextInt(8))),
        paymentMethod: method,
        counterpartyName: customer,
      ));
    }

    // ── Expenses ────────────────────────────────────────────────────────
    if (isFirstOfMonth) {
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.expense,
        title: 'Rent',
        subtitle: 'Rent',
        category: 'Rent',
        amount: roundToNaira(120000 + random.nextDouble() * 60000),
        dateTime: day.add(const Duration(hours: 10)),
        paymentMethod: 'Bank Transfer',
      ));
    }
    if (isFirstOfMonth || isMidMonth) {
      const employees = ['Kwame', 'Halima', 'Emeka'];
      for (final employee in employees) {
        transactions.add(MoneyTransaction(
          id: nextId(),
          type: MoneyTransactionType.expense,
          title: 'Wages — $employee',
          subtitle: 'Wages',
          category: 'Wages',
          amount: roundToNaira(20000 + random.nextDouble() * 25000),
          dateTime: day.add(Duration(hours: 11, minutes: random.nextInt(59))),
          paymentMethod: random.nextDouble() < 0.5 ? 'Bank Transfer' : 'Cash',
          counterpartyName: employee,
        ));
      }
    }
    if (day.day % 10 == 0) {
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.expense,
        title: 'Utilities',
        subtitle: 'Utilities',
        category: 'Utilities',
        amount: roundToNaira(5000 + random.nextDouble() * 12000),
        dateTime: day.add(const Duration(hours: 12)),
        paymentMethod: 'Bank Transfer',
      ));
    }
    if (random.nextDouble() < 0.55) {
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.expense,
        title: 'Transport',
        subtitle: 'Transport',
        category: 'Transport',
        amount: roundToNaira(500 + random.nextDouble() * 2800),
        dateTime: day.add(Duration(hours: 8 + random.nextInt(10))),
        paymentMethod: 'Cash',
      ));
    }
    if (random.nextDouble() < 0.1) {
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.expense,
        title: 'Other expense',
        subtitle: 'Other',
        category: 'Other',
        amount: roundToNaira(1000 + random.nextDouble() * 9000),
        dateTime: day.add(Duration(hours: 13 + random.nextInt(6))),
        paymentMethod: weightedPaymentMethod(),
      ));
    }

    // ── Supplier payments: roughly weekly. ─────────────────────────────
    if (day.weekday == DateTime.wednesday && random.nextDouble() < 0.85) {
      final supplier = supplierNames[random.nextInt(supplierNames.length)];
      transactions.add(MoneyTransaction(
        id: nextId(),
        type: MoneyTransactionType.supplierPayment,
        title: 'Payment — $supplier',
        subtitle: 'Supplier payment',
        amount: roundToNaira(15000 + random.nextDouble() * 75000),
        dateTime: day.add(const Duration(hours: 14)),
        paymentMethod: random.nextDouble() < 0.5 ? 'Bank Transfer' : 'Cash',
        counterpartyName: supplier,
      ));
    }
  }

  transactions.sort((a, b) => b.dateTime.compareTo(a.dateTime));
  return transactions;
}
