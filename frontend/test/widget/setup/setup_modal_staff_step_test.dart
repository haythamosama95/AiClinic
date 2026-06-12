import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/settings/domain/branch_working_schedule.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_modal.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_wizard_nav_bar.dart';

import '../../helpers/auth_test_support.dart';

void main() {
  testWidgets('staff step subtitle requires at least one staff account', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)],
        child: MaterialApp(
          home: Scaffold(body: SetupModal(onFinished: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(SetupModal)));
    final notifier = container.read(setupNotifierProvider.notifier);

    notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
    notifier.continueToStaffStep(
      branchName: 'Main',
      branchCode: 'MAIN',
      address: '123 Street',
      phone: '+20 100 000 0000',
      mapsUrl: 'https://maps.example.com/main',
      workingSchedule: BranchWorkingSchedule.defaultSchedule(),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Create at least one staff account to finish setup. You can add more now or manage staff later in Settings.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Finish stays disabled until a staff draft is added', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)],
        child: MaterialApp(
          home: Scaffold(body: SetupModal(onFinished: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(SetupModal)));
    final notifier = container.read(setupNotifierProvider.notifier);
    (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
      AuthSessionState(
        status: AuthSessionStatus.authenticated,
        context: sampleAuthSessionContext(setupRequired: true, branchIds: const ['branch-local']),
      ),
    );

    notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
    notifier.continueToStaffStep(
      branchName: 'Main',
      branchCode: 'MAIN',
      address: '123 Street',
      phone: '+20 100 000 0000',
      mapsUrl: 'https://maps.example.com/main',
      workingSchedule: BranchWorkingSchedule.defaultSchedule(),
    );
    await tester.pumpAndSettle();

    final navBar = tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar));
    expect(navBar.nextLabel, 'Finish');
    expect(navBar.nextEnabled, isFalse);

    notifier.addStaffDraft(
      username: 'frontdesk',
      fullName: 'Front Desk',
      role: StaffRole.receptionist,
      branchIds: const ['branch-local'],
      password: 'Secret12',
    );
    await tester.pumpAndSettle();

    final enabledNavBar = tester.widget<SetupWizardNavBar>(find.byType(SetupWizardNavBar));
    expect(enabledNavBar.nextEnabled, isTrue);
  });
}
