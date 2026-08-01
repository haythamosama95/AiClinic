import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_empty_state.dart';
<<<<<<< HEAD
import 'package:ai_clinic/core/ui/components/app_radio_group.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/appointment_start_doctor_dialog.dart';
=======
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/features/queue/domain/queue_start_doctor.dart';
import 'package:ai_clinic/features/queue/presentation/widgets/queue_start_doctor_dialog.dart';
>>>>>>> master

import 'calendar_widget_test_harness.dart';

void main() {
  const doctorAId = '11111111-1111-4111-8111-111111111111';
  const doctorBId = '22222222-2222-4222-8222-222222222222';

<<<<<<< HEAD
  Future<String?> openDialog(
=======
  Future<PendingDialogResult<String?>> openDialog(
>>>>>>> master
    WidgetTester tester, {
    required List<QueueStartDoctorOption> options,
  }) async {
    late Future<String?> result;
    await pumpDialogShell(
      tester,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () {
<<<<<<< HEAD
            result = AppointmentStartDoctorDialog.show(context, options: options);
=======
            result = QueueStartDoctorDialog.show(context, options: options);
>>>>>>> master
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

  testWidgets('invalid state: CAL-START-DOC-01 empty options shows No doctors available', (tester) async {
    await openDialog(tester, options: const []);

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('No doctors available'), findsOneWidget);
    expect(find.text('Start visit'), findsOneWidget);
    final startButton = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Start visit'));
    expect(startButton.disabled, isTrue);
  });

  testWidgets('advanced: CAL-START-DOC-02 lists available doctors with preferred label', (tester) async {
    await openDialog(
      tester,
      options: const [
        QueueStartDoctorOption(id: doctorAId, name: 'Dr. Ada', isBusy: false, isPreferred: true),
        QueueStartDoctorOption(id: doctorBId, name: 'Dr. Ben', isBusy: true),
      ],
    );

<<<<<<< HEAD
    expect(find.byType(AppRadioGroup), findsOneWidget);
    expect(find.text('Dr. Ada (preferred)'), findsOneWidget);
    expect(find.text('Dr. Ben'), findsNothing);
  });

  testWidgets('advanced: CAL-START-DOC-03 Start visit pops chosen doctor id', (tester) async {
    final resultFuture = await openDialog(
=======
    expect(find.text('Preferred provider'), findsOneWidget);
    expect(find.text('Dr. Ada'), findsWidgets);
    expect(find.text('Preferred'), findsOneWidget);
    expect(find.text('Dr. Ben'), findsOneWidget);
    expect(find.byType(AppBadge), findsWidgets);
  });

  testWidgets('advanced: CAL-START-DOC-03 Start visit pops chosen doctor id', (tester) async {
    final dialog = await openDialog(
>>>>>>> master
      tester,
      options: const [
        QueueStartDoctorOption(id: doctorAId, name: 'Dr. Ada', isBusy: false, isPreferred: true),
        QueueStartDoctorOption(id: doctorBId, name: 'Dr. Ben', isBusy: false),
      ],
    );

    await tester.tap(find.text('Dr. Ben'));
    await tester.pump();
    await tester.tap(find.text('Start visit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

<<<<<<< HEAD
    expect(await resultFuture, doctorBId);
  });

  testWidgets('advanced: CAL-START-DOC-04 Cancel pops null', (tester) async {
    final resultFuture = await openDialog(
      tester,
      options: const [
        QueueStartDoctorOption(id: doctorAId, name: 'Dr. Ada', isBusy: false),
      ],
=======
    expect(await dialog.result, doctorBId);
  });

  testWidgets('advanced: CAL-START-DOC-04 Cancel pops null', (tester) async {
    final dialog = await openDialog(
      tester,
      options: const [QueueStartDoctorOption(id: doctorAId, name: 'Dr. Ada', isBusy: false)],
>>>>>>> master
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

<<<<<<< HEAD
    expect(await resultFuture, isNull);
=======
    expect(await dialog.result, isNull);
>>>>>>> master
  });

  testWidgets('regression: CAL-START-DOC-05 barrier tap does not dismiss dialog', (tester) async {
    await openDialog(
      tester,
<<<<<<< HEAD
      options: const [
        QueueStartDoctorOption(id: doctorAId, name: 'Dr. Ada', isBusy: false),
      ],
=======
      options: const [QueueStartDoctorOption(id: doctorAId, name: 'Dr. Ada', isBusy: false)],
>>>>>>> master
    );

    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Who will see this patient?'), findsOneWidget);
  });
}
