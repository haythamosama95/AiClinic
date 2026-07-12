import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

import 'package:ai_clinic/features/appointments/domain/appointment_calendar_display.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';

/// Resource id for appointments without an assigned doctor.
const appointmentCalendarUnassignedResourceId = '__unassigned__';

/// Syncfusion data source for branch appointment rows.
class AppointmentCalendarDataSource extends CalendarDataSource {
  Set<AppointmentStatus> _highlightedStatuses = const {};

  AppointmentCalendarDataSource(List<AppointmentListItem> items, {List<StaffListItem> doctors = const []}) {
    _apply(
      items,
      doctors,
      includeDoctorResources: false,
      evenResourceRowColor: Colors.transparent,
      oddResourceRowColor: Colors.transparent,
    );
  }

  void updateItems(
    List<AppointmentListItem> items, {
    List<StaffListItem> doctors = const [],
    required bool includeDoctorResources,
    Color evenResourceRowColor = Colors.transparent,
    Color oddResourceRowColor = Colors.transparent,
    Set<AppointmentStatus>? highlightedStatuses,
  }) {
    if (highlightedStatuses != null) {
      _highlightedStatuses = highlightedStatuses;
    }
    _apply(
      items,
      doctors,
      includeDoctorResources: includeDoctorResources,
      evenResourceRowColor: evenResourceRowColor,
      oddResourceRowColor: oddResourceRowColor,
    );
    notifyListeners(CalendarDataSourceAction.reset, appointments ?? const []);
  }

  void _apply(
    List<AppointmentListItem> items,
    List<StaffListItem> doctors, {
    required bool includeDoctorResources,
    required Color evenResourceRowColor,
    required Color oddResourceRowColor,
  }) {
    appointments = _mapAppointments(
      items,
      assignResources: includeDoctorResources,
      highlightedStatuses: _highlightedStatuses,
    );
    resources = includeDoctorResources
        ? _mapDoctorResources(doctors, evenRowColor: evenResourceRowColor, oddRowColor: oddResourceRowColor)
        : const [];
  }

  static List<Appointment> _mapAppointments(
    List<AppointmentListItem> items, {
    required bool assignResources,
    required Set<AppointmentStatus> highlightedStatuses,
  }) {
    return [
      for (final item in items)
        Appointment(
          id: item.id,
          startTime: item.startTime.toLocal(),
          endTime: item.endTime.toLocal(),
          subject: item.patientName,
          notes: assignResources ? null : item.doctorDisplayName,
          color: AppointmentCalendarDisplay.appointmentTileColor(item.status, highlightedStatuses),
          resourceIds: assignResources ? _resourceIdsFor(item) : null,
        ),
    ];
  }

  static List<Object>? _resourceIdsFor(AppointmentListItem item) {
    final doctorId = item.doctorId?.trim();
    if (doctorId == null || doctorId.isEmpty) {
      return const [appointmentCalendarUnassignedResourceId];
    }
    return [doctorId];
  }

  static List<CalendarResource> _mapDoctorResources(
    List<StaffListItem> doctors, {
    required Color evenRowColor,
    required Color oddRowColor,
  }) {
    final resources = <CalendarResource>[];
    var index = 0;
    for (final doctor in doctors) {
      resources.add(
        CalendarResource(id: doctor.id, displayName: doctor.fullName, color: index.isEven ? evenRowColor : oddRowColor),
      );
      index++;
    }
    resources.add(
      CalendarResource(
        id: appointmentCalendarUnassignedResourceId,
        displayName: 'Unassigned',
        color: index.isEven ? evenRowColor : oddRowColor,
      ),
    );
    return resources;
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

/// Maps a tapped timeline resource to a doctor id, if applicable.
String? doctorIdFromCalendarResource(CalendarResource? resource) {
  if (resource == null) {
    return null;
  }
  final id = resource.id.toString();
  if (id == appointmentCalendarUnassignedResourceId) {
    return null;
  }
  return id;
}
