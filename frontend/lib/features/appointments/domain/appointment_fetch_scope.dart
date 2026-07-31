import 'package:flutter/foundation.dart';

import 'package:ai_clinic/features/auth/domain/auth_session.dart';

/// Session fields that determine which branch appointments are loaded for.
@immutable
class AppointmentFetchScope {
  const AppointmentFetchScope({
    this.activeBranchId,
    this.organizationId,
    this.organizationTimezone,
  });

  final String? activeBranchId;
  final String? organizationId;
  final String? organizationTimezone;

  factory AppointmentFetchScope.fromContext(AuthSessionContext? context) {
    if (context == null) {
      return const AppointmentFetchScope();
    }
    return AppointmentFetchScope(
      activeBranchId: _normalizedOrNull(context.activeBranchId),
      organizationId: _normalizedOrNull(context.organizationId),
      organizationTimezone: _normalizedOrNull(context.organizationTimezone),
    );
  }

  static String? _normalizedOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppointmentFetchScope &&
            activeBranchId == other.activeBranchId &&
            organizationId == other.organizationId &&
            organizationTimezone == other.organizationTimezone;
  }

  @override
  int get hashCode =>
      Object.hash(activeBranchId, organizationId, organizationTimezone);
}
