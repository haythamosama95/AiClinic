import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_table.dart';

void main() {
  testWidgets('PatientTable renders MRN as first column (US3)', (tester) async {
    const mrn = 'MRN-000042';
    final rows = [
      PatientTableRow(
        item: const PatientListItem(
          id: 'p1',
          fullName: 'Ahmed Hassan',
          mrn: mrn,
          registeringBranchId: 'b1',
          registeringBranchName: 'Main',
        ),
      ),
    ];

    await tester.binding.setSurfaceSize(const Size(1280, 600));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: PatientTable(rows: rows, loading: false)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('MRN'), findsOneWidget);
    expect(find.text(mrn), findsOneWidget);

    final mrnFinder = find.text(mrn);
    final patientFinder = find.text('Ahmed Hassan');
    expect(tester.getTopLeft(mrnFinder).dx < tester.getTopLeft(patientFinder).dx, isTrue);
  });
}
