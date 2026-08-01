<<<<<<< HEAD
=======
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
>>>>>>> master
import 'package:ai_clinic/features/appointments/domain/appointment_list_item.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_status.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_type.dart';
import 'package:ai_clinic/features/appointments/presentation/navigation/appointment_detail_route_extra.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppointmentDetailRouteExtra.fromExtra', () {
    final preview = AppointmentListItem(
      id: 'a1',
      patientId: 'p1',
      patientName: 'Pat',
      startTime: DateTime.utc(2026, 6, 4, 10),
      endTime: DateTime.utc(2026, 6, 4, 10, 30),
      type: AppointmentType.planned,
      status: AppointmentStatus.scheduled,
    );

    test('trivial: AppointmentDetailRouteExtra passes through', () {
      const extra = AppointmentDetailRouteExtra();
      expect(AppointmentDetailRouteExtra.fromExtra(extra), same(extra));
    });

    test('advanced: AppointmentListItem is wrapped as preview', () {
      final parsed = AppointmentDetailRouteExtra.fromExtra(preview);

      expect(parsed.preview, preview);
    });

    test('edge case: null returns empty extra', () {
      final parsed = AppointmentDetailRouteExtra.fromExtra(null);

      expect(parsed.preview, isNull);
    });

    test('stupid usage: unrelated types return empty extra', () {
      expect(AppointmentDetailRouteExtra.fromExtra('string').preview, isNull);
      expect(AppointmentDetailRouteExtra.fromExtra(42).preview, isNull);
      expect(AppointmentDetailRouteExtra.fromExtra({'id': 'a1'}).preview, isNull);
    });
<<<<<<< HEAD
=======

    test('preserves breadcrumbTrail when provided', () {
      final trail = BreadcrumbTrail([
        BreadcrumbEntries.hubQueue(),
        BreadcrumbEntries.appointment('a1', label: 'Pat · Jun 4, 2026'),
      ]);
      final extra = AppointmentDetailRouteExtra(breadcrumbTrail: trail);

      final parsed = AppointmentDetailRouteExtra.fromExtra(extra);

      expect(parsed.breadcrumbTrail, trail);
    });
>>>>>>> master
  });
}
