import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';

/// Syncfusion data source for branch appointment rows.
class AppointmentCalendarDataSource extends CalendarDataSource {
  AppointmentCalendarDataSource(List<AppointmentListItem> items) {
    appointments = _mapAppointments(items);
  }

  void updateItems(List<AppointmentListItem> items) {
    final mapped = _mapAppointments(items);
    appointments = mapped;
    notifyListeners(CalendarDataSourceAction.reset, mapped);
  }

  static List<Appointment> _mapAppointments(List<AppointmentListItem> items) {
    return [
      for (final item in items)
        Appointment(
          id: item.id,
          startTime: item.startTime.toLocal(),
          endTime: item.endTime.toLocal(),
          subject: item.patientName,
          notes: item.doctorDisplayName,
          color: AppointmentCalendarDisplay.statusColor(item.status),
        ),
    ];
  }
}

String? _appointmentId(Appointment? appointment) {
  if (appointment == null) {
    return null;
  }
  final id = appointment.id?.toString();
  if (id == null || id.isEmpty) {
    return null;
  }
  return id;
}

/// Resolves tapped calendar appointment id from [details].
String? appointmentIdFromTap(CalendarTapDetails details) {
  final appointment = details.appointments?.firstOrNull;
  return appointment is Appointment ? _appointmentId(appointment) : null;
}

/// Resolves appointment id from [details] produced by [CalendarAppointmentDetails].
String? appointmentIdFromAppointmentDetails(CalendarAppointmentDetails details) {
  final appointment = details.appointments.firstOrNull;
  return appointment is Appointment ? _appointmentId(appointment) : null;
}
