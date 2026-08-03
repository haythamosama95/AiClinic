import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BreadcrumbTrailNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('needsSyncForLocation is false after setTrail records location', () {
      final notifier = container.read(breadcrumbTrailProvider.notifier);

      notifier.setTrail(
        BreadcrumbTrail([BreadcrumbEntries.hubPatients(), BreadcrumbEntries.patient('p1', name: 'Sara Ali')]),
        syncedLocation: AppRoutes.patientDetail('p1'),
      );

      expect(notifier.needsSyncForLocation(AppRoutes.patientDetail('p1')), isFalse);
      expect(notifier.needsSyncForLocation(AppRoutes.patients), isTrue);
    });

    test('route re-sync preserves resolved labels over stale placeholders', () {
      final notifier = container.read(breadcrumbTrailProvider.notifier);
      notifier.setTrail(
        BreadcrumbTrail([BreadcrumbEntries.hubPatients(), BreadcrumbEntries.patient('p1', name: 'Sara Ali')]),
        syncedLocation: AppRoutes.patients,
      );

      final staleRouteTrail = BreadcrumbTrail([
        BreadcrumbEntries.hubPatients(),
        BreadcrumbEntries.patient('p1', name: '…'),
      ]);

      notifier.setTrail(
        staleRouteTrail.mergePreservedLabelsFrom(container.read(breadcrumbTrailProvider)),
        syncedLocation: AppRoutes.patientDetail('p1'),
      );

      expect((container.read(breadcrumbTrailProvider).entries[1].label as FixedBreadcrumbLabel).text, 'Sara Ali');
    });
  });
}
