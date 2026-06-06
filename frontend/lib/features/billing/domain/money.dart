import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

/// Canonical money amount parsed from billing RPC wire strings (V1-6).
@immutable
class Money implements Comparable<Money> {
  const Money._(this._value);

  final Decimal _value;

  static final zero = Money._(Decimal.zero);

  /// Parses a server or user decimal string (dot separator, scale ≤ 2).
  static Money parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return zero;
    }
    if (trimmed.contains(',')) {
      throw FormatException('Money values must use a dot decimal separator: $raw');
    }
    final parsed = Decimal.tryParse(trimmed);
    if (parsed == null) {
      throw FormatException('Invalid money value: $raw');
    }
    return Money._(parsed);
  }

  static Money? tryParse(String? raw) {
    if (raw == null) {
      return null;
    }
    try {
      return parse(raw);
    } on FormatException {
      return null;
    }
  }

  static Money fromWire(String? raw) => tryParse(raw) ?? zero;

  String get wireValue {
    final scaled = _value.round(scale: 2);
    return scaled.toStringAsFixed(2);
  }

  double get asDouble => _value.toDouble();

  bool get isZero => _value == Decimal.zero;

  bool get isPositive => _value > Decimal.zero;

  bool get isNegative => _value < Decimal.zero;

  Money operator +(Money other) => Money._(_value + other._value);

  Money operator -(Money other) => Money._(_value - other._value);

  @override
  int compareTo(Money other) => _value.compareTo(other._value);

  @override
  String toString() => wireValue;

  @override
  bool operator ==(Object other) => identical(this, other) || other is Money && _value == other._value;

  @override
  int get hashCode => _value.hashCode;
}
