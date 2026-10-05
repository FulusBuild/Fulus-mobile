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

/// Converts a user-entered major-unit number at a local input boundary.\n/// Persisted and wire money must never use this floating-point representation.\nMoney moneyFromMajor(num value) => (value * 100).round();

double moneyToMajor(Money value) => value / 100.0;

String moneyToWire(Money value) {
  final negative = value < 0;
  final absolute = value.abs();
  final major = absolute ~/ 100;
  final minor = absolute % 100;
  return '${negative ? '-' : ''}$major.${minor.toString().padLeft(2, '0')}';
}

Money moneyFromWire(Object? value) {
  if (value is int) return value * 100;
  if (value is double) return moneyFromMajor(value);
  if (value is num) return moneyFromMajor(value);
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) throw const FormatException('Empty monetary value');

    final negative = text.startsWith('-');
    final unsigned = (text.startsWith('-') || text.startsWith('+'))
        ? text.substring(1)
        : text;
    final parts = unsigned.split('.');
    if (parts.length > 2 || parts.isEmpty || parts[0].isEmpty) {
      throw FormatException('Invalid monetary value: $value');
    }

    final major = int.parse(parts[0]);
    final fractional = parts.length == 1 ? '' : parts[1];
    if (fractional.length > 2 || fractional.contains(RegExp(r'[^0-9]'))) {
      throw FormatException('Invalid two-decimal monetary value: $value');
    }
    final minorText = fractional.padRight(2, '0');
    final result = major * 100 + (minorText.isEmpty ? 0 : int.parse(minorText));
    return negative ? -result : result;
  }
  throw FormatException('Unsupported monetary value: $value');
}


class MoneyJsonConverter implements JsonConverter<Money, Object?> {
  const MoneyJsonConverter();

  @override
  Money fromJson(Object? json) => moneyFromWire(json);

  @override
  Object toJson(Money object) => moneyToWire(object);
}
