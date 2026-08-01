import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_textarea.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_cancel_dialog.dart';

import 'calendar_widget_test_harness.dart';

void main() {
<<<<<<< HEAD
  Future<String?> openDialog(WidgetTester tester) async {
=======
  Future<PendingDialogResult<String?>> openDialog(WidgetTester tester) async {
>>>>>>> master
    late Future<String?> result;
    await pumpDialogShell(
      tester,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
            result = AppointmentCancelDialog.show(
              context,
              appointment: calendarAppointmentItem(patientName: 'Jane Doe'),
            );
          },
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
<<<<<<< HEAD
    return result;
=======
    return PendingDialogResult(result);
>>>>>>> master
  }

  testWidgets('trivial: CAL-CANCEL-01 reason AppTextarea is present with maxLength 2000', (tester) async {
    await openDialog(tester);

    expect(find.text('Cancel appointment?'), findsOneWidget);
    expect(find.byType(AppTextarea), findsOneWidget);
    final field = tester.widget<AppTextarea>(find.byType(AppTextarea));
    expect(field.maxLength, 2000);
  });

  testWidgets('advanced: CAL-CANCEL-02 Keep appointment pops null', (tester) async {
<<<<<<< HEAD
    final resultFuture = await openDialog(tester);
=======
    final dialog = await openDialog(tester);
>>>>>>> master

    await tester.tap(find.text('Keep appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

<<<<<<< HEAD
    expect(await resultFuture, isNull);
  });

  testWidgets('advanced: CAL-CANCEL-03 Cancel appointment pops trimmed reason', (tester) async {
    final resultFuture = await openDialog(tester);
=======
    expect(await dialog.result, isNull);
  });

  testWidgets('advanced: CAL-CANCEL-03 Cancel appointment pops trimmed reason', (tester) async {
    final dialog = await openDialog(tester);
>>>>>>> master

    await tester.enterText(find.byType(AppTextarea), '  Patient rescheduled  ');
    await tester.tap(find.text('Cancel appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

<<<<<<< HEAD
    expect(await resultFuture, 'Patient rescheduled');
  });

  testWidgets('edge case: CAL-CANCEL-04 empty reason is allowed', (tester) async {
    final resultFuture = await openDialog(tester);
=======
    expect(await dialog.result, 'Patient rescheduled');
  });

  testWidgets('edge case: CAL-CANCEL-04 empty reason is allowed', (tester) async {
    final dialog = await openDialog(tester);
>>>>>>> master

    await tester.tap(find.text('Cancel appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

<<<<<<< HEAD
    expect(await resultFuture, '');
  });

  testWidgets('edge case: CAL-CANCEL-05 whitespace-only reason trims to empty', (tester) async {
    final resultFuture = await openDialog(tester);
=======
    expect(await dialog.result, '');
  });

  testWidgets('edge case: CAL-CANCEL-05 whitespace-only reason trims to empty', (tester) async {
    final dialog = await openDialog(tester);
>>>>>>> master

    await tester.enterText(find.byType(AppTextarea), '   ');
    await tester.tap(find.text('Cancel appointment'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

<<<<<<< HEAD
    expect(await resultFuture, '');
=======
    expect(await dialog.result, '');
>>>>>>> master
  });
}
