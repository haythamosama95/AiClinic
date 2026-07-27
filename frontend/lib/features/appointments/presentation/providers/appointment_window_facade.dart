import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';

/// Appointment timing metadata for cross-feature visit surfaces.
@immutable
class AppointmentWindow {
  const AppointmentWindow({
    required this.startTime,
    required this.endTime,
    required this.breadcrumbLabel,
  });

  final DateTime startTime;
  final DateTime endTime;
  final String breadcrumbLabel;
}

final _appointmentDateFormat = DateFormat('MMM d, yyyy');

/// Loads appointment window labels for visit documentation and confirmation surfaces.
final appointmentWindowProvider = FutureProvider.autoDispose.family<AppointmentWindow, String>((
  ref,
  appointmentId,
) async {
  final appointment = await ref.watch(appointmentDetailProvider(appointmentId).future);
  final date = _appointmentDateFormat.format(appointment.startTime.toLocal());

  return AppointmentWindow(
    startTime: appointment.startTime,
    endTime: appointment.endTime,
    breadcrumbLabel: '${appointment.patientName} · $date',
  );
});
