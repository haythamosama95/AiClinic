import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/models/appointment_section.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_section_nav.dart';

/// Shared appointments page chrome with sub-navigation tabs.
class AppointmentPageShell extends StatelessWidget {
  const AppointmentPageShell({
    required this.activeSection,
    required this.child,
    this.description = 'Schedule visits, manage the queue, and book appointments.',
    super.key,
  });

  final AppointmentSection activeSection;
  final Widget child;
  final String description;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppPageHeader(
              title: 'Appointments',
              description: description,
              tabs: SizedBox(
                width: double.infinity,
                child: AppointmentSectionNav(activeSection: activeSection),
              ),
            ),
            const SizedBox(height: AppSpacing.space6),
          ],
        );

        final hasBoundedHeight = constraints.maxHeight.isFinite;
        if (!hasBoundedHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [header, child],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
