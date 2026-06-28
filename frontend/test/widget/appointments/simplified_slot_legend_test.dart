import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/features/appointments/presentation/widgets/simplified_slot_legend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SimplifiedSlotLegend', () {
    testWidgets('renders legend labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child!),
          home: const Scaffold(body: SimplifiedSlotLegend()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('simplified_slot_legend')), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Other doctors free'), findsOneWidget);
      expect(find.text('Fully booked'), findsOneWidget);
      expect(find.text('Selected'), findsNothing);
      expect(find.text('9:00'), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.help_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });
  });
}
