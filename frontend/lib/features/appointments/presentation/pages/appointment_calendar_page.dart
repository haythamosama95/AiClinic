import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_panel.dart';

/// Branch appointment calendar (`/appointments/calendar`).
class AppointmentCalendarPage extends ConsumerWidget {
  const AppointmentCalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessAppointmentHub(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Calendar',
        description: 'You do not have permission to view the appointment calendar.',
      );
    }

    final canBook = AuthRouteGuard.canAccessAppointmentBooking(auth);

    return CalendarQueuePattern(
      view: CalendarQueueView.calendar,
      onViewChanged: (_) {},
      toolbarStart: const AppPageHeader(
        title: 'Calendar & schedules',
        description: 'Day, week, and month views for branch appointments.',
      ),
      calendarHeader: const SizedBox.shrink(),
      calendar: AppointmentCalendarPanel(
        title: 'Schedule',
        onBookTap: canBook ? () => context.nav.goAppointmentsBook() : null,
      ),
      queueColumns: const [],
    );
  }
}
