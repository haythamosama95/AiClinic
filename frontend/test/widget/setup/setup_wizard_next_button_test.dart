import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_field_options.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_searchable_field.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';

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
}
