import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';
import 'package:ai_clinic/features/patients/domain/patient_detail.dart';
import 'package:ai_clinic/features/patients/presentation/pages/patient_detail_page.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_history_provider.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_detail_provider.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  testWidgets('Patient detail identity card renders MRN badge first (US4)', (tester) async {
    const patientId = '11111111-1111-4111-8111-111111111111';
    const mrn = 'MRN-000042';
    final detail = PatientDetail(
      id: patientId,
      fullName: 'Ahmed Hassan',
      mrn: mrn,
      branchId: 'b1',
      branchName: 'Main',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

    final auth = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(permissions: const {'patients.view'}),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _AuthHarness(auth)),
          patientDetailProvider(patientId).overrideWith((ref) async => detail),
          patientPastVisitsProvider(patientId).overrideWith((ref) async => []),
          patientUpcomingAppointmentsProvider(
            const PatientDetailHistoryQuery(patientId: patientId, branchId: 'b1'),
          ).overrideWith((ref) async => []),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PatientDetailPage(patientId: patientId)),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text(mrn), findsOneWidget);
    expect(find.byType(AppBadge), findsWidgets);

    final badgeFinder = find.ancestor(of: find.text(mrn), matching: find.byType(AppBadge));
    expect(badgeFinder, findsOneWidget);

    final badge = tester.widget<AppBadge>(badgeFinder);
    expect(badge.color, BadgeColor.teal);
    expect(badge.variant, BadgeVariant.soft);
    expect(badge.size, BadgeSize.md);
  });
}

class _AuthHarness extends AuthSessionNotifier {
  _AuthHarness(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}
