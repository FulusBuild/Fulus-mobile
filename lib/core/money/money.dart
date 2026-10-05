import 'package:json_annotation/json_annotation.dart';

/// Canonical local representation for monetary values.
///
/// Money is stored as integer minor units. For the normal two-decimal
/// currency contract, 100 units = 1 major currency unit.
///
/// The financial domain must not use IEEE-754 floating point for persisted
/// or calculated money. Conversion to/from the existing cloud NUMERIC(14,2)
/// contract is explicit at data/remote boundaries.
typedef Money = int;

const Money zeroMoney = 0;

/// Converts a user-entered major-unit number at a local input boundary.
/// Persisted and wire money must never use this floating-point representation.
Money moneyFromMajor(num value) => (value * 100).round();

double moneyToMajor(Money value) => value / 100.0;

String moneyToWire(Money value) {
  final negative = value < 0;
  final absolute = value.abs();
  final major = absolute ~/ 100;
  final minor = absolute % 100;
  return '${negative ? '-' : ''}$major.${minor.toString().padLeft(2, '0')}';
}

Money moneyFromWire(Object? value) {
  // Cloud monetary values are an explicit decimal-string wire contract.
  // Accepting JSON numbers here is unsafe: PostgreSQL NUMERIC values such as
  // 300.00 can arrive through JSON as the integer 300, which is ambiguous
  // between 300 major units and 300 minor units. The previous implementation
  // guessed that integers were major units and could therefore turn ₦300 into
  // 30,000 minor units during canonical reconciliation/restore.
  if (value is! String) {
    throw FormatException('Unsupported monetary wire value: $value');
  }

  final text = value.trim();
  if (!RegExp(r'^-?\d+\.\d{2}$').hasMatch(text)) {
    throw FormatException(
      'Monetary wire values must be decimal strings with exactly two decimals: $value',
    );
  }

  final negative = text.startsWith('-');
  final unsigned = negative ? text.substring(1) : text;
  final parts = unsigned.split('.');
  final major = int.parse(parts[0]);
  final minor = int.parse(parts[1]);
  final result = major * 100 + minor;
  return negative ? -result : result;
}


class MoneyJsonConverter implements JsonConverter<Money, Object?> {
  const MoneyJsonConverter();

  @override
  Money fromJson(Object? json) => moneyFromWire(json);

  @override
  Object toJson(Money object) => moneyToWire(object);
}
