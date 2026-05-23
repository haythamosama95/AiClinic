import 'package:ai_clinic/app/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes V1-3 patient management', () {
    test('static patient paths are unique and under /patients', () {
      final paths = AppRoutes.patientStaticPaths;
      expect(paths.toSet().length, paths.length, reason: 'duplicate route constant');

      for (final path in paths) {
        expect(path.startsWith(AppRoutes.patients), isTrue);
      }
    });

    test('static paths match spec segment names', () {
      expect(AppRoutes.patients, '/patients');
      expect(AppRoutes.patientsNew, '/patients/new');
    });

    test('detail path embeds id without double slashes', () {
      const id = '550e8400-e29b-41d4-a716-446655440000';
      expect(AppRoutes.patientDetail(id), '/patients/$id');
    });

    test('edit path nests under detail segment', () {
      const id = 'patient-uuid-1';
      expect(AppRoutes.patientEdit(id), '/patients/$id/edit');
      expect(AppRoutes.patientEdit(id), startsWith(AppRoutes.patientDetail(id)));
    });

    test('parameterized builders preserve opaque ids (slashes, spaces, unicode)', () {
      const weirdIds = ['../escape', '  spaced  ', 'patient/inner', 'مريض-١', ''];
      for (final id in weirdIds) {
        expect(AppRoutes.patientDetail(id), contains(id));
        expect(AppRoutes.patientEdit(id), endsWith('/edit'));
      }
    });

    test('new patient route is not confused with edit segment', () {
      expect(AppRoutes.patientsNew, isNot(endsWith('/edit')));
      expect(AppRoutes.patientsNew.startsWith(AppRoutes.patients), isTrue);
    });

    test('patient routes do not collide with settings admin paths', () {
      for (final adminPath in AppRoutes.adminSettingsPaths) {
        expect(adminPath.startsWith(AppRoutes.patients), isFalse);
      }
      expect(AppRoutes.patientStaticPaths, isNot(contains(AppRoutes.settings)));
    });

    test('regression: auth and settings routes unchanged', () {
      expect(AppRoutes.login, '/login');
      expect(AppRoutes.settingsOrganization, '/settings/organization');
      expect(AppRoutes.home, '/home');
    });
  });
}
