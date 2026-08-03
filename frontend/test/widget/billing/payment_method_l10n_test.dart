import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/billing/domain/payment_method.dart';
import 'package:ai_clinic/features/billing/presentation/utils/payment_method_l10n.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

void main() {
  testWidgets('PaymentMethod.labelFor returns localized labels from ARB', (tester) async {
    final labels = <PaymentMethod, String>{};

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            for (final method in PaymentMethod.values) {
              labels[method] = method.labelFor(context);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(labels[PaymentMethod.cash], 'Cash');
    expect(labels[PaymentMethod.card], 'Card');
    expect(labels[PaymentMethod.bankTransfer], 'Bank transfer');
    expect(labels[PaymentMethod.insuranceSettlement], 'Insurance');
  });
}
