import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/first_sign_in_warning_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FirstSignInWarningDialog shows bootstrap password warning copy', (tester) async {
    var continued = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: AppButton(
                  label: 'Open warning',
                  onPressed: () => FirstSignInWarningDialog.show(context, onContinue: () => continued = true),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open warning'));
    await tester.pumpAndSettle();

    expect(find.text('Change the default password'), findsOneWidget);
    expect(find.textContaining('shipped administrator password'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Continue to clinic setup'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
  });
}
