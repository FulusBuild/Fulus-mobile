/// App-wide display formatting — thousands-separated currency, relative
/// day labels, and 12-hour time.
///
/// Redesign pass: this is the promotion `money_format.dart` itself
/// flagged as future work — "Home (`home_screen.dart`) and Reports
/// (`reports_screen.dart`) both format money as plain
/// `'₦${amount.toStringAsFixed(2)}'` with no separators... a future
/// pass could promote it to `core/utils` for those two screens to
/// share." That gap is real and visible: Money shows `₦58,951,121.00`
/// while Stock/Sell/Cart/Payment/Reports/Home all show the unseparated
/// form on the exact same screenshot session. Logic is identical to
/// `features/money/presentation/utils/money_format.dart` (no `intl`
/// dependency added here either, same "avoid new dependencies unless
/// genuinely necessary" stance) — that file is left in place rather
/// than deleted, since Money's own call sites already import it and
/// re-pointing every one of them is unrelated churn for a visual pass;
/// this is the shared copy every *other* feature now converges on.
library;

String formatMoney(double amount, {String symbol = '₦', bool showSign = false, bool compact = false}) {
  if (compact) return _formatCompactMoney(amount, symbol: symbol, showSign: showSign);
  final isNegative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final wholePart = parts[0];
  final decimalPart = parts[1];

  final buffer = StringBuffer();
  for (var i = 0; i < wholePart.length; i++) {
    if (i > 0 && (wholePart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(wholePart[i]);
  }

  final sign = isNegative ? '-' : (showSign ? '+' : '');
  return '$sign$symbol${buffer.toString()}.$decimalPart';
}

/// A short "₦44.0M" / "₦850.5K" form for tight spaces (stat tiles,
/// compact hero numbers) — never used where the exact figure matters
/// (receipts, transaction rows), only for glanceable summaries.
String _formatCompactMoney(double amount, {String symbol = '₦', bool showSign = false}) {
  final isNegative = amount < 0;
  final abs = amount.abs();
  final sign = isNegative ? '-' : (showSign ? '+' : '');
  String value;
  if (abs >= 1000000000) {
    value = '${(abs / 1000000000).toStringAsFixed(abs >= 10000000000 ? 0 : 1)}B';
  } else if (abs >= 1000000) {
    value = '${(abs / 1000000).toStringAsFixed(abs >= 10000000 ? 0 : 1)}M';
  } else if (abs >= 1000) {
    value = '${(abs / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}K';
  } else {
    value = abs.toStringAsFixed(0);
  }
  return '$sign$symbol$value';
}

/// Compact "today / yesterday / 12 Mar" style date label for a
/// transaction row or section header.
String formatRelativeDay(DateTime dateTime) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final local = dateTime.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final label = '${day.day} ${months[day.month - 1]}';
  return day.year == today.year ? label : '$label ${day.year}';
}

String formatTime(DateTime dateTime) {
  final hour24 = dateTime.toLocal().hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = dateTime.toLocal().minute.toString().padLeft(2, '0');
  final period = hour24 < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

/// "Good morning" / "Good afternoon" / "Good evening" — Home's greeting
/// header. No Bible citation for this exact copy (Home was a
/// single-hero screen before this pass — see `home_screen.dart`); kept
/// deliberately plain rather than inventing a persona-driven tone.
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
