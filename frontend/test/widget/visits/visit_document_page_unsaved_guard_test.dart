import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_unsaved_changes_guard.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisitDocumentPage unsaved changes guard', () {
    testWidgets('shows dialog on pop when documentation is dirty and stay keeps the route', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) {
                return;
              }
              final context = navigatorKey.currentContext;
              if (context == null) {
                return;
              }
              final decision = await showVisitUnsavedChangesDialog(context);
              if (decision == VisitExitDecision.stay) {
                return;
              }
              if (context.mounted) {
                await Navigator.of(context).maybePop();
              }
            },
            child: const Scaffold(body: Text('Visit documentation workspace')),
          ),
        ),
      );

      expect(find.text('Unsaved documentation'), findsNothing);

      expect(navigatorKey.currentState!.canPop(), isFalse);
      final handled = await tester.binding.handlePopRoute();
      expect(handled, isTrue);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Unsaved documentation'), findsOneWidget);

      await tester.tap(find.text('Stay on page'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Visit documentation workspace'), findsOneWidget);
      expect(find.text('Unsaved documentation'), findsNothing);
    });
  });
}
