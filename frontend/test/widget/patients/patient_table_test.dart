import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/utils/patient_presentation_formatting.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_table.dart';

const _dashPlaceholder = '—';

PatientTableRow _row({
  required String id,
  required String fullName,
  String? mrn,
  String? phone,
  DateTime? dateOfBirth,
  DateTime? lastVisitAt,
  DateTime? nextAppointmentAt,
}) {
  return PatientTableRow(
    item: PatientListItem(
      id: id,
      fullName: fullName,
      mrn: mrn,
      phone: phone,
      dateOfBirth: dateOfBirth,
      lastVisitAt: lastVisitAt,
      nextAppointmentAt: nextAppointmentAt,
      registeringBranchId: 'branch-a',
      registeringBranchName: 'Branch A',
    ),
  );
}

Future<void> _pumpTable(
  WidgetTester tester, {
  required List<PatientTableRow> rows,
  bool loading = false,
  int loadingRows = 5,
  ValueChanged<PatientTableRow>? onRowClick,
  Widget? emptyState,
  Widget? errorState,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 600));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PatientTable(
          rows: rows,
          loading: loading,
          loadingRows: loadingRows,
          onRowClick: onRowClick,
          emptyState: emptyState,
          errorState: errorState,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PatientTable', () {
    testWidgets('trivial: renders a row per item with expected column values', (tester) async {
      final lastVisit = DateTime.utc(2026, 2, 10);
      final nextVisit = DateTime.utc(2026, 3, 15, 14, 30);
      final rows = [
        _row(
          id: 'p1',
          fullName: 'Ahmed Hassan',
          mrn: 'MRN-000042',
          phone: '+201234567890',
          dateOfBirth: DateTime.utc(1990, 1, 15),
          lastVisitAt: lastVisit,
          nextAppointmentAt: nextVisit,
        ),
        _row(
          id: 'p2',
          fullName: 'Sara Ali',
          mrn: 'MRN-000043',
          phone: '+201098765432',
          dateOfBirth: DateTime.utc(1988, 6, 20),
        ),
      ];

      await _pumpTable(tester, rows: rows);

      expect(find.text('Ahmed Hassan'), findsOneWidget);
      expect(find.text('Sara Ali'), findsOneWidget);
      expect(find.text('MRN-000042'), findsOneWidget);
      expect(find.text('MRN-000043'), findsOneWidget);
      expect(find.text('+201234567890'), findsOneWidget);
      expect(
        find.text(PatientPresentationFormatting.dateOfBirthLabel(DateTime.utc(1990, 1, 15))),
        findsOneWidget,
      );
      expect(
        find.text(PatientPresentationFormatting.date.format(lastVisit)),
        findsOneWidget,
      );
      expect(
        find.text(PatientPresentationFormatting.dateTime.format(nextVisit)),
        findsOneWidget,
      );
    });

    testWidgets('trivial: loading state renders the configured number of loading rows', (tester) async {
      await _pumpTable(
        tester,
        rows: const [],
        loading: true,
        loadingRows: 2,
      );

      expect(find.byType(AppSkeleton), findsNWidgets(12));
    });

    testWidgets('trivial: empty state and error state render when supplied', (tester) async {
      await _pumpTable(
        tester,
        rows: const [],
        emptyState: const Text('No patients match'),
      );

      expect(find.text('No patients match'), findsOneWidget);

      await _pumpTable(
        tester,
        rows: const [],
        errorState: const Text('Could not load patients'),
      );

      expect(find.text('Could not load patients'), findsOneWidget);
    });

    testWidgets('advanced: onRowClick fires with the tapped row', (tester) async {
      final rows = [
        _row(id: 'p1', fullName: 'Ahmed Hassan', mrn: 'MRN-000042'),
        _row(id: 'p2', fullName: 'Sara Ali', mrn: 'MRN-000043'),
      ];
      PatientTableRow? tapped;

      await _pumpTable(
        tester,
        rows: rows,
        onRowClick: (row) => tapped = row,
      );

      await tester.tap(find.text('Sara Ali'));
      await tester.pumpAndSettle();

      expect(tapped?.item.id, 'p2');
      expect(tapped?.item.fullName, 'Sara Ali');
    });

    testWidgets('edge case: null MRN renders dash placeholder', (tester) async {
      await _pumpTable(
        tester,
        rows: [
          _row(id: 'p1', fullName: 'No Mrn Patient', mrn: null),
        ],
      );

      expect(find.text(_dashPlaceholder), findsWidgets);
      expect(find.text('No Mrn Patient'), findsOneWidget);
    });
  });
}
