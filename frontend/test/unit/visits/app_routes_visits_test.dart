import 'package:ai_clinic/app/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoutes V1-5 visit medical records', () {
    test('visit path builders match spec segments', () {
      const visitId = '550e8400-e29b-41d4-a716-446655440000';
      expect(AppRoutes.visitDocument(visitId), '/visits/$visitId/document');
      expect(AppRoutes.visitDetail(visitId), '/visits/$visitId/detail');
    });

    test('parameterized builders preserve opaque visit ids', () {
      const weirdIds = ['../escape', '  spaced  ', 'visit/inner', 'زيارة-١', ''];
      for (final id in weirdIds) {
        expect(AppRoutes.visitDocument(id), contains(id));
        expect(AppRoutes.visitDocument(id), startsWith('${AppRoutes.visits}/'));
        expect(AppRoutes.visitDetail(id), contains(id));
        expect(AppRoutes.visitDetail(id), endsWith('/detail'));
      }
    });

    test('visit routes do not collide with appointment or patient paths', () {
      for (final path in AppRoutes.appointmentStaticPaths) {
        expect(path.startsWith(AppRoutes.visits), isFalse);
      }
      for (final path in AppRoutes.patientStaticPaths) {
        expect(path.startsWith(AppRoutes.visits), isFalse);
      }
      expect(AppRoutes.visits.startsWith(AppRoutes.appointments), isFalse);
      expect(AppRoutes.visits.startsWith(AppRoutes.patients), isFalse);
    });

    test('regression: prior route constants unchanged', () {
      expect(AppRoutes.appointments, '/appointments');
      expect(AppRoutes.patients, '/patients');
      expect(AppRoutes.login, '/login');
      expect(AppRoutes.home, '/home');
    });

    test('stupid user: all visit paths are absolute and slash-safe', () {
      const visitId = 'abc-123';
      final paths = [AppRoutes.visitDocument(visitId), AppRoutes.visitDetail(visitId)];

      for (final path in paths) {
        expect(path.startsWith('/'), isTrue);
        expect(path.contains('//'), isFalse);
      }
    });

    test('document and detail paths differ only by terminal segment', () {
      const visitId = 'visit-1';
      final document = AppRoutes.visitDocument(visitId);
      final detail = AppRoutes.visitDetail(visitId);
      expect(document.replaceAll('/document', ''), detail.replaceAll('/detail', ''));
    });
  });
}
