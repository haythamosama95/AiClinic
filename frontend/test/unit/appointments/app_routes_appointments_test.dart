import 'package:ai_clinic/app/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes V1-4 appointment management', () {
    test('static appointment paths are unique and under /appointments', () {
      final paths = AppRoutes.appointmentStaticPaths;
      expect(paths.toSet().length, paths.length, reason: 'duplicate route constant');

      for (final path in paths) {
        expect(path.startsWith(AppRoutes.appointments), isTrue);
      }
    });

    test('static paths match spec segment names', () {
      expect(AppRoutes.appointments, '/appointments');
      expect(AppRoutes.appointmentsBook, '/appointments/book');
      expect(AppRoutes.appointmentsWalkIn, '/appointments/walk-in');
      expect(AppRoutes.appointmentsQueue, '/appointments/queue');
      expect(AppRoutes.appointmentsCalendar, '/appointments/calendar');
    });

    test('schedule path embeds doctor id without double slashes', () {
      const doctorId = '550e8400-e29b-41d4-a716-446655440000';
      expect(AppRoutes.appointmentsSchedule(doctorId), '/appointments/schedule/$doctorId');
    });

    test('parameterized schedule builder preserves opaque ids', () {
      const weirdIds = ['../escape', '  spaced  ', 'doctor/inner', 'طبيب-١', ''];
      for (final id in weirdIds) {
        expect(AppRoutes.appointmentsSchedule(id), contains(id));
        expect(AppRoutes.appointmentsSchedule(id), startsWith('${AppRoutes.appointments}/schedule/'));
      }
    });

    test('book and walk-in routes are distinct', () {
      expect(AppRoutes.appointmentsBook, isNot(AppRoutes.appointmentsWalkIn));
      expect(AppRoutes.appointmentsBook, isNot(endsWith('/walk-in')));
      expect(AppRoutes.appointmentsWalkIn, endsWith('/walk-in'));
    });

    test('appointment routes do not collide with patient or settings paths', () {
      for (final patientPath in AppRoutes.patientStaticPaths) {
        expect(patientPath.startsWith(AppRoutes.appointments), isFalse);
      }
      for (final adminPath in AppRoutes.adminSettingsPaths) {
        expect(adminPath.startsWith(AppRoutes.appointments), isFalse);
      }
      expect(AppRoutes.appointmentStaticPaths, isNot(contains(AppRoutes.patients)));
    });

    test('regression: auth, patient, and settings routes unchanged', () {
      expect(AppRoutes.login, '/login');
      expect(AppRoutes.patients, '/patients');
      expect(AppRoutes.settingsOrganization, '/settings/organization');
      expect(AppRoutes.home, '/home');
    });

    test('stupid user: all appointment paths are absolute and slash-safe', () {
      final paths = [...AppRoutes.appointmentStaticPaths, AppRoutes.appointmentsSchedule('doc-1')];

      for (final path in paths) {
        expect(path.startsWith('/'), isTrue);
        expect(path.contains('//'), isFalse);
      }
    });
  });
}
