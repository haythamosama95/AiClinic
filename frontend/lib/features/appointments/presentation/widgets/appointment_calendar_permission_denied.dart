import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_page_shell.dart';

/// Permission-denied placeholder for the appointment calendar route.
class AppointmentCalendarPermissionDenied extends StatelessWidget {
  const AppointmentCalendarPermissionDenied({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppointmentPageShell(child: AppEmptyState(variant: AppEmptyStateVariant.noAccess));
  }
}
