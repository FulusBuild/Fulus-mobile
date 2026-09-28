/// Thousands-separated currency formatting. No `intl` dependency added
/// — per this codebase's own "avoid new dependencies unless genuinely
/// necessary" stance (see `csv_export_service.dart`'s equivalent
/// choice) — this is a few lines of real formatting logic, not
/// something that needs a whole package.
///
/// Home (`home_screen.dart`) and Reports (`reports_screen.dart`) both
/// format money as plain `'₦${amount.toStringAsFixed(2)}'` with no
/// separators — left as-is, since those are feature-owned files this
/// task isn't touching. This formatter is Money-feature-local; a
/// future pass could promote it to `core/utils` for those two screens
/// to share.
String formatMoney(double amount, {String symbol = '₦', bool showSign = false}) {
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
