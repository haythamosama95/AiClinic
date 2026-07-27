import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/presentation/pages/visit_document_page.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import '../../helpers/auth_test_support.dart';
import '../../support/visit_encounter_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VisitDocumentPage unsaved changes guard', () {
    testWidgets('shows dialog on pop when documentation is dirty and stay keeps the route', (tester) async {
      final visitDetailGate = Completer<VisitDetailViewState>();

      await tester.binding.setSurfaceSize(const Size(1280, 900));

      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _AuthHarness(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(
                    permissions: {PermissionKeys.visitsEditSoap, PermissionKeys.visitsCreate},
                  ),
                ),
              ),
            ),
            visitDetailViewProvider(encounterTestVisitId).overrideWith((ref) => visitDetailGate.future),
            visitDocumentationProvider(encounterTestVisitId).overrideWith(_DirtyVisitDocNotifier.new),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Text('Home')),
            routes: {
              '/visit': (_) => VisitDocumentPage(visitId: encounterTestVisitId),
            },
          ),
        ),
      );

      navigatorKey.currentState!.pushNamed('/visit');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(VisitDocumentPage), findsOneWidget);
      expect(find.text('Unsaved documentation'), findsNothing);

      final popped = await navigatorKey.currentState!.maybePop();
      expect(popped, isFalse);

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Unsaved documentation'), findsOneWidget);

      await tester.tap(find.text('Stay on page'));
      await tester.pumpAndSettle();

      expect(find.byType(VisitDocumentPage), findsOneWidget);
      expect(find.text('Unsaved documentation'), findsNothing);
    });
  });
}

class _DirtyVisitDocNotifier extends VisitDocumentationNotifier {
  @override
  Future<VisitDocumentationState> build() async {
    return sampleEncounterDocState().copyWith(complaint: 'Unsaved draft');
  }
}

class _AuthHarness extends AuthSessionNotifier {
  _AuthHarness(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
