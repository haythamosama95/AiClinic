import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpNavBar(WidgetTester tester, {required SetupWizardNavBar navBar, bool wrapped = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: wrapped ? SizedBox(width: 400, child: navBar) : navBar),
      ),
    );
    await tester.pump();
  }

  testWidgets('hides nav bar when showBack and showNext false', (tester) async {
    await pumpNavBar(tester, navBar: const SetupWizardNavBar(showBack: false, showNext: false));

    expect(find.byType(AppButton), findsNothing);
  });

  testWidgets('Back disabled while isBusy', (tester) async {
    await pumpNavBar(
      tester,
      navBar: SetupWizardNavBar(showBack: true, showNext: true, isBusy: true, onBack: () {}, onNext: () {}),
    );

    expect(tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar)).isBusy, isTrue);
  });

  testWidgets('Next shows loading state when isBusy', (tester) async {
    await pumpNavBar(
      tester,
      navBar: SetupWizardNavBar(showNext: true, nextLabel: 'Finish', nextEnabled: true, isBusy: true, onNext: () {}),
    );

    final navBar = tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar));
    expect(navBar.isBusy, isTrue);
    expect(navBar.nextLabel, 'Finish');
  });

  testWidgets('disabled Next shows tooltip and absorbs pointer', (tester) async {
    var nextTapped = false;
    await pumpNavBar(
      tester,
      navBar: SetupWizardNavBar(
        showNext: true,
        nextEnabled: false,
        nextDisabledTooltip: 'Need more fields',
        onNext: () => nextTapped = true,
      ),
    );

    expect(find.byType(Tooltip), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, 'Need more fields');

    await tester.tap(find.widgetWithText(AppButton, 'Next'));
    await tester.pump();
    expect(nextTapped, isFalse);
  });

  testWidgets('embedded mode omits leading Spacer', (tester) async {
    await pumpNavBar(
      tester,
      navBar: SetupWizardNavBar(embedded: true, showNext: true, nextEnabled: true, onNext: () {}),
      wrapped: false,
    );

    expect(find.byType(Spacer), findsNothing);
    expect(find.widgetWithText(AppButton, 'Next'), findsOneWidget);
  });

  testWidgets('non-embedded mode includes leading Spacer', (tester) async {
    await pumpNavBar(tester, navBar: SetupWizardNavBar(showNext: true, nextEnabled: true, onNext: () {}));

    expect(find.byType(Spacer), findsOneWidget);
  });
}
