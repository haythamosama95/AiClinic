import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_modal.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  Future<void> pumpModal(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)],
        child: MaterialApp(
          home: Scaffold(body: SetupModal(onFinished: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('organization step shows guide subtitle', (tester) async {
    await pumpModal(tester);

    expect(find.text("Enter your clinic's organization details to get started."), findsOneWidget);
  });

  testWidgets('modal initializes with default currency and timezone enabling Next after name', (tester) async {
    await pumpModal(tester);

    expect(find.text(BootstrapCurrencyOptions.defaultCode), findsWidgets);
    expect(find.text(BootstrapTimezoneOptions.defaultZone), findsWidgets);

    await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), 'Sunrise Clinic');
    await tester.pump();

    final navBar = tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar));
    expect(navBar.nextEnabled, isTrue);
  });
}
