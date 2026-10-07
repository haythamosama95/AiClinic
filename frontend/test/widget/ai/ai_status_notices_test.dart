import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/ai/availability/ai_availability.dart';
import 'package:ai_clinic/features/ai/presentation/pages/ai_page.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
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
  });

  final String noticeCode;
  final int? daysLeft;

  @override
  Future<AiAvailability> read() async {
    return const AiAvailability(
      enrolled: true,
      platformBaseUrl: testPlatformBaseUrl,
    );
  }
}
