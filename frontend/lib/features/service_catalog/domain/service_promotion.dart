import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/billing/domain/money.dart';

/// Time-boxed promotion window for a (service, branch) pair (Service Catalog 015 US4).
@immutable
class ServicePromotion {
  const ServicePromotion({required this.price, required this.startDate, required this.endDate});

  final Money price;
  final DateTime startDate;
  final DateTime endDate;

  /// Whether the promotion applies on [date] (inclusive start and end).
  bool isActiveOn(DateTime date) {
    final day = _dateOnly(date);
    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  bool isExpiredOn(DateTime date) => !isActiveOn(date);

  String get wirePrice => price.wireValue;

  String get wireStartDate => _wireDate(startDate);

  String get wireEndDate => _wireDate(endDate);

  static ServicePromotion? tryParse({String? price, String? startDate, String? endDate}) {
    if (price == null || startDate == null || endDate == null) {
      return null;
    }
    final parsedPrice = Money.tryParse(price);
    final parsedStart = _parseDate(startDate);
    final parsedEnd = _parseDate(endDate);
    if (parsedPrice == null || parsedStart == null || parsedEnd == null) {
      return null;
    }
    return ServicePromotion(price: parsedPrice, startDate: parsedStart, endDate: parsedEnd);
  }

  static DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  static DateTime? _parseDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return DateTime.tryParse(trimmed);
  }

  static String _wireDate(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
