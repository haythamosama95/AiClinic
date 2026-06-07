import 'package:ai_clinic/features/shifts/presentation/widgets/shift_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('notes field enforces maxLength and trimmed validator (#11)', (tester) async {
    final notesController = TextEditingController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            child: ShiftFormFields(
              shiftDate: DateTime(2026, 6, 10),
              startTime: const TimeOfDay(hour: 9, minute: 0),
              endTime: const TimeOfDay(hour: 17, minute: 0),
              notesController: notesController,
              onShiftDateChanged: (_) {},
              onStartTimeChanged: (_) {},
              onEndTimeChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('shift_notes_field')), findsOneWidget);

    notesController.text = '  ${'x' * 501}  ';
    final formState = tester.state<FormState>(find.byType(Form));
    expect(formState.validate(), isFalse);
  });
}
