import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import 'ai_surface_test_harness.dart';

void main() {
  group('E2E-P6.1-03', () {
    for (final daysLeft in [7, 3, 1]) {
      testWidgets('E2E-P6.1-03 ends_soon at $daysLeft days renders staff and administrator notice forms', (
        tester,
      ) async {
        await _pumpLiveSurface(
          tester,
          reader: _NoticeScenarioReader(
            noticeCode: 'ends_soon',
            daysLeft: daysLeft,
          ),
          role: StaffRole.doctor,
        );

        expect(find.textContaining('ask your administrator', findRichText: true), findsOneWidget);
        expect(find.textContaining(RegExp(r'\$|EGP|price|payment|purchase', caseSensitive: false)), findsNothing);
        expect(find.byKey(const Key('ai_notice_renew')), findsNothing);

        await _pumpLiveSurface(
          tester,
          reader: _NoticeScenarioReader(
            noticeCode: 'ends_soon',
            daysLeft: daysLeft,
          ),
          role: StaffRole.administrator,
        );

        expect(find.byKey(const Key('ai_notice_renew')), findsOneWidget);
      });
    }
  });

  group('R7-UI3 status notice copy', () {
    final en = lookupAppLocalizations(const Locale('en'));

    testWidgets('R7-UI3: in_grace shows days left', (tester) async {
      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'in_grace', graceDaysLeft: 4),
        role: StaffRole.doctor,
      );
      expect(find.text(en.aiNoticeInGraceStaff(4)), findsOneWidget);
      expect(find.textContaining('in_grace'), findsNothing);

      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'in_grace', graceDaysLeft: 4),
        role: StaffRole.administrator,
      );
      expect(find.text(en.aiNoticeInGraceAdmin(4)), findsOneWidget);
      expect(find.byKey(const Key('ai_notice_renew')), findsOneWidget);
    });

    testWidgets('R7-UI3: in_grace with zero days reads as less than one day, not a completed grace', (tester) async {
      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'in_grace', graceDaysLeft: 0),
        role: StaffRole.receptionist,
      );
      expect(find.text(en.aiNoticeInGraceStaff(0)), findsOneWidget);
      expect(find.textContaining('less than one day'), findsOneWidget);

      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'in_grace', graceDaysLeft: 0),
        role: StaffRole.administrator,
      );
      expect(find.text(en.aiNoticeInGraceAdmin(0)), findsOneWidget);
    });

    testWidgets('R7-UI3: in_grace renders Arabic text in the Arabic locale', (tester) async {
      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'in_grace', graceDaysLeft: 2),
        role: StaffRole.doctor,
        locale: const Locale('ar'),
      );
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(ar.aiNoticeInGraceStaff(2)), findsOneWidget);
      expect(find.text(ar.aiNoticeAskAdministrator), findsOneWidget);
    });

    testWidgets('R7-UI3: unknown status code shows neutral text, never the wire code', (tester) async {
      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'mystery_code'),
        role: StaffRole.doctor,
      );
      expect(find.text(en.aiNoticeUnavailable), findsOneWidget);
      expect(find.textContaining('mystery_code'), findsNothing);
    });
  });

  group('E2E-P6.1-04', () {
    testWidgets('E2E-P6.1-04 allowance_low renders staff and administrator notice forms', (tester) async {
      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'allowance_low'),
        role: StaffRole.receptionist,
      );

      expect(find.textContaining('ask your administrator', findRichText: true), findsOneWidget);
      expect(find.textContaining(RegExp(r'\$|EGP|price|payment|purchase', caseSensitive: false)), findsNothing);
      expect(find.byKey(const Key('ai_notice_renew')), findsNothing);

      await _pumpLiveSurface(
        tester,
        reader: const _NoticeScenarioReader(noticeCode: 'allowance_low'),
        role: StaffRole.administrator,
      );

      expect(find.byKey(const Key('ai_notice_renew')), findsOneWidget);
    });
  });
}

Future<void> _pumpLiveSurface(
  WidgetTester tester, {
  required _NoticeScenarioReader reader,
  required StaffRole role,
  Locale locale = const Locale('en'),
}) async {
  final harness = AiSurfaceHarness(skipReachabilityProbe: true);

  final composition = buildLiveVisitSummaryComposition(
    client: _FakeSupabaseClient(),
    visitId: testVisitId,
    availabilityReader: reader,
    reachabilityPort: harness.reachabilityPort,
    mintPortOverride: harness.mintPort,
    submitPortOverride: harness.submitPort,
    networkSpy: harness.networkSpy,
    persistenceProbe: harness.persistenceProbe,
    exportProbe: harness.exportProbe,
    contextProviderOverride: harness.contextProvider,
    manifestRefreshPortOverride: harness.manifestRefreshPort,
    autoInvoke: false,
    staffIsAdministrator: role == StaffRole.administrator,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authSessionProvider.overrideWith(
          () => MutableAuthSessionNotifier(
            AuthSessionState(
              status: AuthSessionStatus.authenticated,
              context: sampleAuthSessionContext(role: role),
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: liveVisitSummaryHostBody(visitId: testVisitId, composition: composition),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {}

class _NoticeScenarioReader implements AiAvailabilityReader {
  const _NoticeScenarioReader({
    required this.noticeCode,
    this.daysLeft,
    this.graceDaysLeft,
  });

  final String noticeCode;
  final int? daysLeft;
  final int? graceDaysLeft;

  @override
  Future<AiAvailability> read() async {
    return AiAvailability(
      enrolled: true,
      platformBaseUrl: testPlatformBaseUrl,
      daysLeft: daysLeft,
      notices: [
        AiStatusNotice(
          code: noticeCode,
          audience: 'member',
          channel: 'in_app',
          graceDaysLeft: graceDaysLeft,
        ),
      ],
    );
  }
}
