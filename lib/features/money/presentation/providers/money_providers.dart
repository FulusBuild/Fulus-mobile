import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../domain/entities/business_settings.dart';
import '../../../../domain/entities/customer.dart';
import '../../../../domain/entities/customer_ledger_entry.dart';
import '../../../../domain/entities/report.dart';
import '../../../../domain/entities/supplier.dart';
import '../../../../domain/entities/supplier_ledger_entry.dart';
import '../../../../domain/usecases/reports_engine.dart';
import '../../data/money_repository.dart';
import '../../data/mock_money_repository.dart';

/// A single [MockMoneyRepository] instance for the whole app session —
/// not `autoDispose`, deliberately, so the generated transaction list
/// (and anything recorded into it via Add Income/Add Expense) stays
/// consistent as the person moves between the Cash Flow screen,
/// History, and Detail rather than regenerating every time the Money
/// tab is reopened.
final moneyRepositoryProvider = Provider<MoneyRepository>((ref) => MockMoneyRepository());

/// Volume 8's shared period selector (Today / This Week / This Month /
/// Custom) — one selection drives the Cash Flow screen, the breakdown
/// sections, and History together, the same "one view" framing the
/// Bible uses for Cash Flow itself.
final moneyPeriodKindProvider = StateProvider<ReportPeriodKind>((ref) => ReportPeriodKind.today);

/// Only meaningful when [moneyPeriodKindProvider] is
/// [ReportPeriodKind.custom] — set via `showDateRangePicker` at the
/// call site (`period_filter_bar.dart`).
final customMoneyRangeProvider = StateProvider<DateTimeRange?>((ref) => null);

const _reportsEngine = ReportsEngine();

/// The resolved [ReportPeriod] every Money screen actually queries
/// against — reactive to both providers above, so nothing downstream
/// has to re-derive this itself or handle a not-yet-chosen custom range
/// as a special case.
final moneyPeriodProvider = Provider<ReportPeriod>((ref) {
  final kind = ref.watch(moneyPeriodKindProvider);
  if (kind == ReportPeriodKind.custom) {
    final range = ref.watch(customMoneyRangeProvider);
    if (range == null) {
      // Custom was picked but no range chosen yet (e.g. the date
      // picker was dismissed) — today is a safer default than a null
      // period every call site would otherwise need to guard against.
      return _reportsEngine.resolvePeriod(ReportPeriodKind.today);
    }
    return _reportsEngine.resolvePeriod(kind, customStart: range.start, customEnd: range.end);
  }
  return _reportsEngine.resolvePeriod(kind);
});

/// The active business's currency symbol, for every amount Money
/// renders — real data, via the already-wired
/// [businessSettingsRepositoryProvider]. Falls back to '₦' (matching
/// Home's own hardcoded symbol) only for the brief gap before the
/// first value arrives, not as a silent substitute for real settings.
final moneyCurrencySymbolProvider = StreamProvider<String>((ref) {
  return ref.watch(businessSettingsRepositoryProvider).watchSettings().map((BusinessProfile? profile) {
    return profile?.currencySymbol ?? '₦';
  });
});

// ── Customers (Credit Book) & Suppliers (Pay Supplier) ──────────────────
//
// Unlike everything above, these are wired to the REAL repositories —
// see `money_transaction.dart`'s doc comment for why: Customer/Supplier
// data is business-wide, needs no locationId, and both repositories are
// already fully implemented.

final moneyCustomersProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers();
});

final moneyCustomerLedgerProvider = StreamProvider.family<List<CustomerLedgerEntry>, String>((ref, customerLocalId) {
  return ref.watch(customerCreditRepositoryProvider).watchLedger(customerLocalId);
});

final moneySuppliersProvider = StreamProvider<List<Supplier>>((ref) {
  return ref.watch(supplierRepositoryProvider).watchSuppliers();
});

final moneySupplierLedgerProvider = StreamProvider.family<List<SupplierLedgerEntry>, String>((ref, supplierLocalId) {
  return ref.watch(supplierCreditRepositoryProvider).watchLedger(supplierLocalId);
});
