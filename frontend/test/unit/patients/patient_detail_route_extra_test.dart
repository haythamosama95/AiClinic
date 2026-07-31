import 'dart:ui';

import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_entry.dart';
import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_trail.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/navigation/patient_detail_route_extra.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PatientDetailRouteExtra.fromExtra', () {
    final preview = PatientListItem(
      id: 'p1',
      fullName: 'Sara Ali',
      registeringBranchId: 'branch-1',
      registeringBranchName: 'Main',
    );

    test('trivial: PatientDetailRouteExtra passes through', () {
      const extra = PatientDetailRouteExtra();
      expect(PatientDetailRouteExtra.fromExtra(extra), same(extra));
    });

    test('advanced: PatientListItem is wrapped as preview', () {
      final parsed = PatientDetailRouteExtra.fromExtra(preview);

      expect(parsed.preview, preview);
      expect(parsed.sourceRect, isNull);
    });

    test('carries preview and sourceRect from existing extra', () {
      const sourceRect = Rect.fromLTWH(10, 20, 100, 50);
      final extra = PatientDetailRouteExtra(
        preview: preview,
        sourceRect: sourceRect,
      );

      final parsed = PatientDetailRouteExtra.fromExtra(extra);

      expect(parsed.preview, preview);
      expect(parsed.sourceRect, sourceRect);
    });

    test('edge case: null returns empty extra', () {
      final parsed = PatientDetailRouteExtra.fromExtra(null);

      expect(parsed.preview, isNull);
      expect(parsed.sourceRect, isNull);
    });

    test('stupid usage: unrelated types return empty extra', () {
      expect(PatientDetailRouteExtra.fromExtra('string').preview, isNull);
      expect(PatientDetailRouteExtra.fromExtra(42).preview, isNull);
      expect(
        PatientDetailRouteExtra.fromExtra({'id': 'p1'}).preview,
        isNull,
      );
    });

    test('preserves breadcrumbTrail when provided', () {
      final trail = BreadcrumbTrail([
        BreadcrumbEntries.hubPatients(),
        BreadcrumbEntries.patient('p1', name: 'Sara Ali'),
      ]);
      final extra = PatientDetailRouteExtra(breadcrumbTrail: trail);

      final parsed = PatientDetailRouteExtra.fromExtra(extra);

      expect(parsed.breadcrumbTrail, trail);
    });
  });
}
