import 'package:ai_clinic/app/navigation/breadcrumb/breadcrumb_label.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BreadcrumbLabel', () {
    testWidgets('fixed resolves literal text', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      const label = BreadcrumbLabel.fixed('INV-MAIN-000001');
      expect(label.resolve(capturedContext), 'INV-MAIN-000001');
    });

    testWidgets('l10n resolves via AppLocalizations', (tester) async {
      late BuildContext capturedContext;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final l10n = AppLocalizations.of(capturedContext)!;
      final label = BreadcrumbLabel.l10n((l10n) => l10n.breadcrumbQueue);

      expect(label.resolve(capturedContext), l10n.breadcrumbQueue);
      expect(label.resolve(capturedContext), 'Queue');
    });
  });
}
