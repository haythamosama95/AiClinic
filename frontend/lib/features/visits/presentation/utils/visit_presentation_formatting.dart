import 'package:intl/intl.dart';

import 'package:ai_clinic/features/visits/domain/visit_status.dart';

/// Shared display helpers for visit documentation and detail views.
abstract final class VisitPresentationFormatting {
  static final visitDate = DateFormat.yMMMd();
  static final visitDateTime = DateFormat('MMM d, y · h:mm a');

  static String statusLabel(VisitStatus status) => status.label;

  static String displayVisitId(String id) {
    return id.length > 8 ? id.substring(0, 8).toUpperCase() : id.toUpperCase();
  }

  static String orDash(String? value) =>
      value == null || value.trim().isEmpty ? '—' : value.trim();
}
