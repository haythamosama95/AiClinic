import 'package:ai_clinic/features/appointments/presentation/widgets/conflict_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConflictErrorBanner', () {
    testWidgets('shows conflict message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConflictErrorBanner(message: 'This time slot overlaps another appointment.')),
        ),
      );

      expect(find.byKey(const Key('conflict_error_banner')), findsOneWidget);
      expect(find.text('This time slot overlaps another appointment.'), findsOneWidget);
      expect(find.byIcon(Icons.event_busy), findsOneWidget);
    });
  });
}
