import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_organization_step.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_searchable_field.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_step_transition.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';

void main() {
  testWidgets('clearing searchable field disables Next via onChanged(null)', (tester) async {
    String? currency;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  SetupSearchableField(
                    label: 'Currency code *',
                    options: BootstrapCurrencyOptions.codes,
                    value: currency,
                    onChanged: (value) => setState(() => currency = value),
                  ),
                  SetupWizardNavBar(
                    showNext: true,
                    nextEnabled: currency != null && BootstrapCurrencyOptions.isValid(currency),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(SetupSearchableField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(AppAutocomplete<String>), 'EGP');
    await tester.pumpAndSettle();

    expect(currency, 'EGP');
    expect(find.byType(SetupWizardNavBar), findsOneWidget);

    await tester.enterText(find.byType(AppAutocomplete<String>), '');
    await tester.pumpAndSettle();

    expect(currency, isNull);
  });

  testWidgets('clearing text field updates controller used for readiness', (tester) async {
    final controller = TextEditingController();
    var nextEnabled = false;

    void refresh() => nextEnabled = controller.text.trim().isNotEmpty;

    controller.addListener(() {
      refresh();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              controller.removeListener(refresh);
              controller.addListener(() => setState(refresh));
              return Column(
                children: [
                  AppTextField(label: 'Name *', controller: controller),
                  SetupWizardNavBar(showNext: true, nextEnabled: nextEnabled),
                ],
              );
            },
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(AppTextField), 'Clinic');
    await tester.pump();

    expect(nextEnabled, isTrue);

    await tester.enterText(find.byType(AppTextField), '');
    await tester.pump();

    expect(nextEnabled, isFalse);
  });

  testWidgets('organization name field keeps focus while typing with step transition layout', (tester) async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final logoUrlController = TextEditingController();
    const currency = BootstrapCurrencyOptions.defaultCode;
    const timezone = BootstrapTimezoneOptions.defaultZone;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return ListenableBuilder(
                listenable: Listenable.merge([nameController, logoUrlController]),
                builder: (context, _) {
                  return Column(
                    children: [
                      SetupStepTransition(
                        step: SetupWizardStep.organization,
                        direction: 1,
                        organizationStep: SetupOrganizationStep(
                          formKey: formKey,
                          nameController: nameController,
                          logoUrlController: logoUrlController,
                          currency: currency,
                          timezone: timezone,
                          onCurrencyChanged: (_) {},
                          onTimezoneChanged: (_) {},
                          isBusy: false,
                        ),
                        branchStep: const SizedBox.shrink(),
                        staffStep: const SizedBox.shrink(),
                        completeStep: const SizedBox.shrink(),
                      ),
                      SetupWizardNavBar(showNext: true, nextEnabled: nameController.text.trim().isNotEmpty),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppTextField, 'Organization name *'));
    await tester.pump();

    final focusBefore = FocusManager.instance.primaryFocus;
    expect(focusBefore, isNotNull);

    await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), 'Demo');
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, focusBefore);
    expect(nameController.text, 'Demo');
  });
}
