import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 setup: routes + domain stubs wire together for later repositories/UI.
void main() {
  group('Appointments phase 1 integration', () {
    test('route builders produce paths parseable as GoRouter segments', () {
      const doctorId = 'd1';

      final paths = [
        AppRoutes.appointments,
        AppRoutes.appointmentsBook,
        AppRoutes.appointmentsWalkIn,
        AppRoutes.appointmentsQueue,
        AppRoutes.appointmentsSchedule(doctorId),
      ];

      for (final path in paths) {
        expect(path.startsWith('/'), isTrue);
        expect(path.contains('//'), isFalse);
        expect(path.split('/').where((s) => s.isEmpty).length, lessThanOrEqualTo(1));
      }
    });

    test('domain models deserialize list_appointments-shaped payloads consistently', () {
      const row = {
        'id': 'a1',
        'patient_id': 'p1',
        'patient_name': 'Patient',
        'doctor_id': 'd1',
        'doctor_name': 'Doctor',
        'start_time': '2026-05-27T09:00:00.000Z',
        'end_time': '2026-05-27T09:20:00.000Z',
        'type': 'planned',
        'status': 'scheduled',
      };

      final listItem = AppointmentListItem.fromRow(row);
      expect(listItem, isNotNull);
      expect(listItem!.type, AppointmentType.planned);
      expect(listItem.status, AppointmentStatus.scheduled);
    });

    test('detail model extends list fields with branch and audit metadata', () {
      final detail = AppointmentDetail.fromRow({
        'id': 'a1',
        'branch_id': 'b1',
        'patient_id': 'p1',
        'patient_name': 'Patient',
        'doctor_id': 'd1',
        'doctor_name': 'Doctor',
        'start_time': '2026-05-27T09:00:00.000Z',
        'end_time': '2026-05-27T09:20:00.000Z',
        'type': 'walk_in',
        'status': 'checked_in',
        'created_at': '2026-05-27T08:00:00.000Z',
        'updated_at': '2026-05-27T08:00:00.000Z',
      });

      expect(detail, isNotNull);
      expect(detail!.branchId, 'b1');
      expect(detail.type, AppointmentType.walkIn);
      expect(detail.status, AppointmentStatus.checkedIn);
    });

    test('invalid states: malformed rows fail closed without throwing', () {
      expect(() => AppointmentListItem.fromRow({}), returnsNormally);
      expect(AppointmentListItem.fromRow({}), isNull);
      expect(() => AppointmentDetail.fromRow({'id': 'only-id'}), returnsNormally);
      expect(AppointmentDetail.fromRow({'id': 'only-id'}), isNull);
    });

    test('regression: patient and settings routes remain available alongside appointments', () {
      expect(AppRoutes.patients, '/patients');
      expect(AppRoutes.settingsBranches, '/settings/branches');
      expect(AppRoutes.appointments.startsWith('/appointments'), isTrue);
    });
  });
}
