import 'package:ai_clinic/features/appointments/presentation/widgets/syncfusion_calendar_hover_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('forwards taps to the guarded child', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncfusionCalendarHoverGuard(
            child: GestureDetector(
              onTap: () => tapped = true,
              child: Container(width: 200, height: 200, color: Colors.blue),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(100, 100));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
