import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/navigation/app_stepper.dart';

void main() {
  final steps = [
    const AppStepperStep(title: 'Step 1', description: 'First step', page: Text('Page 1')),
    const AppStepperStep(title: 'Step 2', description: 'Second step', page: Text('Page 2')),
    const AppStepperStep(title: 'Step 3', page: Text('Page 3')),
  ];

  Future<void> pumpStepper(
    WidgetTester tester, {
    required Widget stepper,
    double width = 720,
    double height = 480,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: Scaffold(
          body: SizedBox(width: width, height: height, child: stepper),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AppStepper', () {
    testWidgets('shows the initial step page', (tester) async {
      await pumpStepper(tester, stepper: AppStepper(steps: steps, initialStep: 0));

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsNothing);
    });

    testWidgets('navigates when a step is tapped', (tester) async {
      await pumpStepper(tester, stepper: AppStepper(steps: steps));

      await tester.tap(find.text('Step 3'));
      await tester.pumpAndSettle();

      expect(find.text('Page 3'), findsOneWidget);
      expect(find.text('Page 1'), findsNothing);
    });

    testWidgets('animates track fill when the active step changes', (tester) async {
      var activeStep = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return SizedBox(
                  width: 720,
                  height: 480,
                  child: AppStepper(
                    steps: steps,
                    currentStep: activeStep,
                    onStepChanged: (index) => setState(() => activeStep = index),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Step 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const Key('app_stepper_track')), findsOneWidget);

      await tester.pumpAndSettle();
    });

    testWidgets('fades between pages on step change', (tester) async {
      await pumpStepper(
        tester,
        stepper: AppStepper(steps: steps, pageTransitionDuration: const Duration(milliseconds: 200)),
      );

      expect(find.text('Page 1'), findsOneWidget);

      await tester.tap(find.text('Step 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final fade = tester.widget<FadeTransition>(
        find.descendant(of: find.byKey(const Key('app_page_fade_transition')), matching: find.byType(FadeTransition)),
      );
      expect(fade.opacity.value, lessThan(1));

      await tester.pumpAndSettle();
      expect(find.text('Page 2'), findsOneWidget);

      final settledFade = tester.widget<FadeTransition>(
        find.descendant(of: find.byKey(const Key('app_page_fade_transition')), matching: find.byType(FadeTransition)),
      );
      expect(settledFade.opacity.value, 1);
    });

    testWidgets('renders horizontal step labels and descriptions', (tester) async {
      await pumpStepper(
        tester,
        stepper: AppStepper(steps: steps, axis: Axis.horizontal),
      );

      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('First step'), findsOneWidget);
      expect(find.text('Step 3'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
    });

    testWidgets('marks completed steps with a check icon after navigation', (tester) async {
      await pumpStepper(tester, stepper: AppStepper(steps: steps, initialStep: 2));

      expect(find.text('Page 3'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
    });

    testWidgets('supports vertical layout', (tester) async {
      await pumpStepper(
        tester,
        stepper: AppStepper(steps: steps, axis: Axis.vertical, initialStep: 1),
      );

      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Second step'), findsOneWidget);
    });
  });
}
