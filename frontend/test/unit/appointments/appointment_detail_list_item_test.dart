import 'package:ai_clinic/features/appointments/domain/appointment_detail.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/utils/appointment_detail_list_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentDetail.toListItem', () {
    final start = DateTime.utc(2026, 6, 4, 10);
    final end = DateTime.utc(2026, 6, 4, 10, 30);
    final createdAt = DateTime.utc(2026, 6, 3, 8);
    final updatedAt = DateTime.utc(2026, 6, 4, 9);

    AppointmentDetail detail({
      String? doctorId,
      String? doctorName,
      int? queueNumber,
      String? notes,
    }) {
      return AppointmentDetail(
        id: 'a1',
        branchId: 'b1',
        patientId: 'p1',
        patientName: 'Pat One',
        doctorId: doctorId,
        doctorName: doctorName,
        startTime: start,
        endTime: end,
        type: AppointmentType.planned,
        status: AppointmentStatus.confirmed,
        queueNumber: queueNumber,
        notes: notes,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    test('trivial: maps every bridged field to AppointmentListItem', () {
      final source = detail(
        doctorId: 'd1',
        doctorName: 'Dr Alpha',
        queueNumber: 12,
        notes: 'Bring labs',
      );

      final listItem = source.toListItem();

      expect(listItem.id, source.id);
      expect(listItem.patientId, source.patientId);
      expect(listItem.patientName, source.patientName);
      expect(listItem.doctorId, 'd1');
      expect(listItem.doctorName, 'Dr Alpha');
      expect(listItem.startTime, start);
      expect(listItem.endTime, end);
      expect(listItem.type, AppointmentType.planned);
      expect(listItem.status, AppointmentStatus.confirmed);
      expect(listItem.updatedAt, updatedAt);
    });

    test('edge case: null optional doctor fields remain null on list item', () {
      final source = detail(doctorId: null, doctorName: null);

      final listItem = source.toListItem();

      expect(listItem.doctorId, isNull);
      expect(listItem.doctorName, isNull);
      expect(source.doctorDisplayName, 'Unassigned');
      expect(listItem.doctorDisplayName, 'Unassigned');
    });

    test('edge case: blank doctor name uses Unassigned display fallback', () {
      final source = detail(doctorId: 'd1', doctorName: '   ');

      expect(source.doctorDisplayName, 'Unassigned');
      expect(source.toListItem().doctorName, '   ');
      expect(source.toListItem().doctorDisplayName, 'Unassigned');
    });

    test('advanced: queueNumber and notes are not bridged to list item', () {
      final source = detail(queueNumber: 7, notes: 'Note');

      final listItem = source.toListItem();

      expect(listItem.id, source.id);
      expect(listItem.updatedAt, updatedAt);
    });
  });
}
