import 'package:ai_clinic/features/appointments/presentation/widgets/duration_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DurationField', () {
    testWidgets('trivial: shows label and validates empty input', (tester) async {
      final controller = TextEditingController();
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.always,
              child: DurationField(
                controller: controller,
                startTime: DateTime(2026, 6, 1, 10),
                minMinutes: 5,
                maxMinutes: 240,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Duration (minutes)'), findsOneWidget);
      expect(formKey.currentState!.validate(), isFalse);
    });

    testWidgets('advanced: shows end-time preview when valid', (tester) async {
      final controller = TextEditingController(text: '30');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationField(
              controller: controller,
              startTime: DateTime(2026, 6, 1, 10),
              minMinutes: 5,
              maxMinutes: 240,
            ),
          ),
        ),
      );

      expect(find.textContaining('Ends at'), findsOneWidget);
    });

    testWidgets('stupid usage: rejects duration below minimum', (tester) async {
      final controller = TextEditingController(text: '2');
      final formKey = GlobalKey<FormState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.always,
              child: DurationField(
                controller: controller,
                startTime: DateTime(2026, 6, 1, 10),
                minMinutes: 5,
                maxMinutes: 240,
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
    });

    testWidgets('edge case: disabled field does not accept input', (tester) async {
      final controller = TextEditingController(text: '20');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationField(
              controller: controller,
              startTime: DateTime(2026, 6, 1, 10),
              minMinutes: 5,
              maxMinutes: 240,
              enabled: false,
            ),
          ),
        ),
      );

      expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled, isFalse);
    });
  });
}
