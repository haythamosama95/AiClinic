import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_modal.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_indicator.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_test_support.dart';

void main() {
  group('SetupModal flow', () {
    testWidgets('step indicator shows three labeled stages on organization step', (tester) async {
      await pumpSetupModal(tester);

      expect(find.byType(SetupStepIndicator), findsOneWidget);
      expect(find.text('Organization'), findsOneWidget);
      expect(find.text('Branch'), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
    });

    testWidgets('organization step shows required fields', (tester) async {
      await pumpSetupModal(tester);

      expect(find.widgetWithText(AppTextField, 'Organization name *'), findsOneWidget);
      expect(find.text('Currency code *'), findsOneWidget);
      expect(find.text('Timezone *'), findsOneWidget);
    });

    testWidgets('branch step shows required fields', (tester) async {
      await pumpSetupModal(tester);
      await advanceSetupModalToBranch(tester);

      expect(find.widgetWithText(AppTextField, 'Branch name *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Branch code *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Address *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Phone *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Maps URL *'), findsOneWidget);
    });

    testWidgets('staff step shows create form fields', (tester) async {
      final container = await pumpSetupModal(tester);
      setBootstrapAdminSession(container);
      await advanceSetupModalToStaff(tester);

      expect(find.widgetWithText(AppTextField, 'Full name *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Username *'), findsOneWidget);
      expect(find.widgetWithText(AppTextField, 'Initial password *'), findsOneWidget);
      expect(find.text('Role *'), findsOneWidget);
    });

    testWidgets('branch step shows branch subtitle', (tester) async {
      await pumpSetupModal(tester);
      await advanceSetupModalToBranch(tester);

      expect(find.text('Start with your main branch. Additional branches can be added later.'), findsOneWidget);
    });

    testWidgets('setup modal has floating card styling and max width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pumpSetupModal(tester, size: const Size(1400, 900));

      final modal = tester.getSize(find.byType(SetupModal));
      expect(modal.width, lessThanOrEqualTo(920));
    });

    testWidgets('modal content is wrapped in scroll view', (tester) async {
      await pumpSetupModal(tester);

      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('complete step shows ready subtitle', (tester) async {
      final container = await pumpSetupModal(tester);
      container.read(setupNotifierProvider.notifier).markSetupComplete();
      await tester.pumpAndSettle();

      expect(find.text('Your clinic is ready to use.'), findsOneWidget);
      expect(find.text('Clinic setup is complete'), findsOneWidget);
    });

    testWidgets('clearing branch name disables Next', (tester) async {
      await pumpSetupModal(tester);
      await advanceSetupModalToBranch(tester);

      await tester.enterText(find.widgetWithText(AppTextField, 'Branch name *'), '');
      await tester.pump();

      final navBar = tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar));
      expect(navBar.nextEnabled, isFalse);
    });

    testWidgets('clearing branch code disables Next', (tester) async {
      await pumpSetupModal(tester);
      await advanceSetupModalToBranch(tester);

      await tester.enterText(find.widgetWithText(AppTextField, 'Branch code *'), '');
      await tester.pump();

      final navBar = tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar));
      expect(navBar.nextEnabled, isFalse);
    });

    testWidgets('branch name keeps focus while typing', (tester) async {
      await pumpSetupModal(tester);
      await advanceSetupModalToBranch(tester);

      await tester.tap(find.widgetWithText(AppTextField, 'Branch name *'));
      await tester.pump();
      final focusBefore = FocusManager.instance.primaryFocus;

      await tester.enterText(find.widgetWithText(AppTextField, 'Branch name *'), 'Downtown');
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, focusBefore);
    });

    testWidgets('adding staff draft shows acknowledgement alert with credentials', (tester) async {
      final container = await pumpSetupModal(tester);
      setBootstrapAdminSession(container);
      await advanceSetupModalToStaff(tester);
      await addStaffDraftViaForm(tester, username: 'frontdesk', password: 'Secret12');

      expect(find.text('Staff member added'), findsOneWidget);
      expect(find.textContaining('Username: frontdesk'), findsOneWidget);
      expect(find.textContaining('Password: Secret12'), findsOneWidget);
    });

    testWidgets('form fields cleared after successful draft add', (tester) async {
      final container = await pumpSetupModal(tester);
      setBootstrapAdminSession(container);
      await advanceSetupModalToStaff(tester);
      await addStaffDraftViaForm(tester);

      expect(find.widgetWithText(AppTextField, 'Username *'), findsOneWidget);
      final usernameField = tester.widget<AppTextField>(find.widgetWithText(AppTextField, 'Username *'));
      expect(usernameField.controller?.text, isEmpty);
    });

    testWidgets('acknowledgement cleared when leaving staff step', (tester) async {
      final container = await pumpSetupModal(tester);
      setBootstrapAdminSession(container);
      await advanceSetupModalToStaff(tester);
      await addStaffDraftViaForm(tester);
      expect(find.text('Staff member added'), findsOneWidget);

      await tapSetupBack(tester);
      expect(find.text('Staff member added'), findsNothing);
    });
  });
}
