import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patients_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/patient_test_support.dart';
import 'patients_list_test_support.dart';

void main() {
  group('K. Frontend UI / Visual (UI)', () {
    group('UI-001 — Table column alignment', () {
      testWidgets('header labels align with row cells at desktop width', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: samplePatientList(count: 2)));

        for (final label in ['Patient', 'Age/Gender', 'Contact', 'Last Visit', 'Next Appointment']) {
          expect(find.text(label), findsOneWidget);
        }

        final patientHeaderX = tester.getTopLeft(find.text('Patient')).dx;
        final patientCellX = tester.getTopLeft(find.text('Patient 001')).dx;
        expect(patientCellX, greaterThanOrEqualTo(patientHeaderX));
      });
    });

    group('UI-003 — Next appointment badge', () {
      testWidgets('shows accent AppBadge with formatted datetime', (tester) async {
        final appointmentAt = DateTime(2026, 6, 1, 9, 0);
        await pumpPatientsPage(
          tester,
          patientsListHost(
            patients: [samplePatientListItem(fullName: 'Scheduled Patient').copyWith(nextAppointmentAt: appointmentAt)],
          ),
        );

        final badge = tester.widget<AppBadge>(find.byType(AppBadge));
        expect(badge.variant, AppBadgeVariant.accent);
        expect(badge.label, contains('Jun'));
      });
    });

    group('UI-004 — Sort popover badge', () {
      testWidgets('dot badge visible when sort is non-default', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: samplePatientList(count: 2)));

        var badge = tester.widget<Badge>(
          find.ancestor(of: find.byIcon(Icons.sort_outlined), matching: find.byType(Badge)),
        );
        expect(badge.isLabelVisible, isFalse);

        await openPatientsSortPopover(tester);
        await tester.tap(find.text('Z to A'));
        await tester.pumpAndSettle();

        badge = tester.widget<Badge>(find.ancestor(of: find.byIcon(Icons.sort_outlined), matching: find.byType(Badge)));
        expect(badge.isLabelVisible, isTrue);
      });
    });

    group('UI-005 — Dark mode tokens', () {
      testWidgets('list page uses dark theme brightness', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: samplePatientList(count: 2), theme: AppTheme.dark()));

        final context = tester.element(find.byType(PatientsTable));
        expect(Theme.of(context).brightness, Brightness.dark);
      });
    });

    group('UI-006 — Page slide direction', () {
      testWidgets('next page triggers slide transition', (tester) async {
        await pumpPatientsPage(tester, patientsListHost(patients: samplePatientList(count: 25)));

        await tester.tap(find.byTooltip('Next page'));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(SlideTransition), findsWidgets);
        await tester.pumpAndSettle();
        expect(find.text('Patient 021'), findsOneWidget);
      });
    });
  });
}
