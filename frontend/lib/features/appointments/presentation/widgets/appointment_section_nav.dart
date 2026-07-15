import 'package:flutter/material.dart';

import 'package:ai_clinic/app/navigation/app_navigator.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/models/appointment_section.dart';

/// Appointments sub-navigation tabs (hub, queue, calendar, book).
class AppointmentSectionNav extends StatelessWidget {
  const AppointmentSectionNav({required this.activeSection, super.key});

  final AppointmentSection activeSection;

  @override
  Widget build(BuildContext context) {
    return AppTabs(
      items: [
        for (final section in appointmentSections)
          AppTabItem(id: section.id, label: section.label, icon: section.icon),
      ],
      value: activeSection.id,
      onChanged: (id) => _navigateToSection(context, AppointmentSection.byId(id)),
      ariaLabel: 'Appointments sections',
    );
  }

  void _navigateToSection(BuildContext context, AppointmentSection? section) {
    if (section == null || section == activeSection) {
      return;
    }

    final nav = context.nav;
    switch (section) {
      case AppointmentSection.hub:
        nav.goAppointments();
      case AppointmentSection.queue:
        nav.goAppointmentsQueue();
      case AppointmentSection.calendar:
        nav.goAppointmentsCalendar();
      case AppointmentSection.book:
        nav.goAppointmentsBook();
    }
  }
}
