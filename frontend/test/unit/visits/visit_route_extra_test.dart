import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/features/visits/presentation/navigation/visit_route_extra.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VisitRouteExtra.fromExtra', () {
    final sampleTrail = BreadcrumbTrail([
      BreadcrumbEntries.hubPatients(),
      BreadcrumbEntries.visitDocument('visit-1'),
    ]);

    test('trivial: VisitRouteExtra passes through', () {
      final extra = VisitRouteExtra(breadcrumbTrail: sampleTrail);
      expect(VisitRouteExtra.fromExtra(extra), same(extra));
    });

    test('reads breadcrumbTrail from other BreadcrumbRouteExtra payloads', () {
      final parsed = VisitRouteExtra.fromExtra(
        VisitRouteExtra(breadcrumbTrail: sampleTrail),
      );

      expect(parsed.breadcrumbTrail, sampleTrail);
    });

    test('edge case: null returns empty extra', () {
      final parsed = VisitRouteExtra.fromExtra(null);

      expect(parsed.breadcrumbTrail, isNull);
    });

    test('stupid usage: unrelated types return empty extra', () {
      expect(VisitRouteExtra.fromExtra('string').breadcrumbTrail, isNull);
      expect(VisitRouteExtra.fromExtra(42).breadcrumbTrail, isNull);
    });
  });
}
