import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/appointments/data/appointment_repository.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_org_calendar.dart';

@immutable
class AppointmentDetailSiblingsQuery {
  const AppointmentDetailSiblingsQuery({required this.branchId, required this.startTime});

  final String branchId;
  final DateTime startTime;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppointmentDetailSiblingsQuery &&
            runtimeType == other.runtimeType &&
            branchId == other.branchId &&
            startTime == other.startTime;
  }

  @override
  int get hashCode => Object.hash(branchId, startTime);
}

/// Same-day appointments at the appointment branch — used for doctor-busy rules on the detail page.
final appointmentDetailSiblingsProvider = FutureProvider.autoDispose
    .family<List<AppointmentListItem>, AppointmentDetailSiblingsQuery>((ref, query) async {
      final branchId = query.branchId.trim();
      if (branchId.isEmpty) {
        return const [];
      }

      final timezone = effectiveOrganizationTimezone(ref.read(authSessionProvider).context?.organizationTimezone);
      final day = calendarDayInOrganizationTimezone(timezone, query.startTime);
      final range = appointmentTodayRangeInTimezone(timezone, day.toUtc());

      final items = await ref
          .read(appointmentRepositoryProvider)
          .listAppointments(branchId: branchId, from: range.from, to: range.to);
      return items;
    });
