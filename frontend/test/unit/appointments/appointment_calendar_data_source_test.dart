import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart' as domain;
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_calendar_data_source.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/settings/domain/staff_list_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';

void main() {
  group('AppointmentCalendarDataSource', () {
    final doctors = [
      const StaffListItem(id: 'doc-1', fullName: 'Dr. Ada', role: StaffRole.doctor, isActive: true),
      const StaffListItem(id: 'doc-2', fullName: 'Dr. Ben', role: StaffRole.doctor, isActive: true),
    ];

    AppointmentListItem sampleItem({String? doctorId}) {
      return AppointmentListItem(
        id: 'appt-1',
        patientId: 'patient-1',
        patientName: 'Jane Doe',
        doctorId: doctorId,
        startTime: DateTime.utc(2026, 6, 15, 10),
        endTime: DateTime.utc(2026, 6, 15, 10, 30),
        type: domain.AppointmentType.planned,
        status: AppointmentStatus.scheduled,
      );
    }

    test('maps doctor resources when resource view is enabled', () {
      final dataSource = AppointmentCalendarDataSource([sampleItem(doctorId: 'doc-1')], doctors: doctors);
      dataSource.updateItems([sampleItem(doctorId: 'doc-1')], doctors: doctors, includeDoctorResources: true);

      expect(dataSource.resources, hasLength(3));
      expect(
        dataSource.resources!.map((resource) => resource.id),
        containsAll(['doc-1', 'doc-2', appointmentCalendarUnassignedResourceId]),
      );
      final appointment = dataSource.appointments!.single as Appointment;
      expect(appointment.resourceIds, ['doc-1']);
      expect(appointment.notes, isNull);
    });

    test('clears resources outside doctor resource view', () {
      final dataSource = AppointmentCalendarDataSource(const [], doctors: doctors);
      dataSource.updateItems([sampleItem()], doctors: doctors, includeDoctorResources: false);

      expect(dataSource.resources, isEmpty);
      final appointment = dataSource.appointments!.single as Appointment;
      expect(appointment.resourceIds, isNull);
      expect(appointment.notes, 'Unassigned');
    });

    test('routes unassigned appointments to unassigned resource', () {
      final dataSource = AppointmentCalendarDataSource(const [], doctors: doctors);
      dataSource.updateItems([sampleItem()], doctors: doctors, includeDoctorResources: true);

      final appointment = dataSource.appointments!.single as Appointment;
      expect(appointment.resourceIds, [appointmentCalendarUnassignedResourceId]);
    });
  });

  group('doctorIdFromCalendarResource', () {
    test('returns null for unassigned resource', () {
      expect(
        doctorIdFromCalendarResource(
          CalendarResource(id: appointmentCalendarUnassignedResourceId, displayName: 'Unassigned'),
        ),
        isNull,
      );
    });

    test('returns doctor id for doctor resource', () {
      expect(doctorIdFromCalendarResource(CalendarResource(id: 'doc-1', displayName: 'Dr. Ada')), 'doc-1');
    });
  });
}
