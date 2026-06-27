import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/domain/appointment_queue_start_doctor.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/queue/queue_shift_doctor_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QueueShiftDoctorPickerDialog', () {
    const options = [
      QueueStartDoctorOption(id: 'doc-a', name: 'Dr Alpha', isBusy: false),
      QueueStartDoctorOption(id: 'doc-b', name: 'Dr Beta', isBusy: false),
      QueueStartDoctorOption(id: 'doc-c', name: 'Dr Gamma', isBusy: true),
    ];

    Future<void> openDialog(WidgetTester tester, {List<QueueStartDoctorOption> dialogOptions = options}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: AppButton(
                  label: 'Open dialog',
                  onPressed: () => QueueShiftDoctorPickerDialog.show(context, options: dialogOptions),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
    }

    testWidgets('renders doctor options inside AppDialog without Material errors', (tester) async {
      await openDialog(tester);

      expect(find.text('Confirm doctor'), findsOneWidget);
      expect(find.text('Dr Alpha'), findsOneWidget);
      expect(find.text('Dr Beta'), findsOneWidget);
      expect(find.text('Dr Gamma'), findsOneWidget);
      expect(find.text('Available'), findsNWidgets(2));
      expect(find.text('Busy — patient in progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting an available doctor and confirming returns their id', (tester) async {
      String? selectedDoctorId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: AppButton(
                  label: 'Open dialog',
                  onPressed: () async {
                    selectedDoctorId = await QueueShiftDoctorPickerDialog.show(context, options: options);
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dr Alpha'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start visit'));
      await tester.pumpAndSettle();

      expect(selectedDoctorId, 'doc-a');
    });

    testWidgets('shows preferred doctor copy and badge when appointment has preferred doctor', (tester) async {
      const preferredOptions = [
        QueueStartDoctorOption(id: 'doc-a', name: 'Dr Alpha', isBusy: true, isPreferred: true),
        QueueStartDoctorOption(id: 'doc-b', name: 'Dr Beta', isBusy: false),
      ];

      await openDialog(tester, dialogOptions: preferredOptions);

      expect(find.text('Confirm doctor'), findsOneWidget);
      expect(
        find.text(
          'Dr Alpha is the preferred doctor but is currently busy. Another doctor is available — select who will see this patient.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Preferred ·'), findsOneWidget);
    });

    testWidgets('pre-selects available preferred doctor', (tester) async {
      const preferredOptions = [
        QueueStartDoctorOption(id: 'doc-a', name: 'Dr Alpha', isBusy: false, isPreferred: true),
        QueueStartDoctorOption(id: 'doc-b', name: 'Dr Beta', isBusy: false),
      ];

      String? selectedDoctorId;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: AppButton(
                  label: 'Open dialog',
                  onPressed: () async {
                    selectedDoctorId = await QueueShiftDoctorPickerDialog.show(context, options: preferredOptions);
                  },
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start visit'));
      await tester.pumpAndSettle();

      expect(selectedDoctorId, 'doc-a');
    });

    testWidgets('shows dialog even when only one doctor is available', (tester) async {
      const singleDoctor = [QueueStartDoctorOption(id: 'doc-b', name: 'Dr Beta', isBusy: false)];

      await openDialog(tester, dialogOptions: singleDoctor);

      expect(find.text('Confirm doctor'), findsOneWidget);
      expect(find.text('Confirm which doctor will see this patient.'), findsOneWidget);
      expect(find.text('Start visit'), findsOneWidget);
    });
  });
}
