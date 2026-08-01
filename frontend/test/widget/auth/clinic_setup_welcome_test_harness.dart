// Test-only harness for clinic setup welcome scope widget tests.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
<<<<<<< HEAD
=======
import 'package:flutter_riverpod/misc.dart';
>>>>>>> master
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_dialog.dart';
import 'package:ai_clinic/features/auth/presentation/widgets/clinic_setup_welcome_scope.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_hydration_provider.dart';
import 'package:ai_clinic/features/setup/presentation/providers/clinic_setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/setup/setup_draft_models.dart';

import '../../helpers/auth_test_support.dart';

/// Sentinel key proving [ClinicSetupWelcomeScope] always renders its child.
const scopeChildSentinelKey = Key('clinic-setup-welcome-scope-child');

/// Controllable [ClinicSetupState] for scope tests — no network or persistence.
<<<<<<< HEAD
class TestClinicSetupNotifier extends StateNotifier<ClinicSetupState> {
  TestClinicSetupNotifier(ClinicSetupState initial) : super(initial);

  void replace(ClinicSetupState next) => state = next;
=======
class TestClinicSetupNotifier extends ClinicSetupNotifier {
  TestClinicSetupNotifier(super.ref, ClinicSetupState initial) {
    state = initial;
  }

  void replace(ClinicSetupState next) => state = next;

  @override
  Future<void> loadDraft() async {}
>>>>>>> master
}

/// Builds an [AuthSessionContext] with a specific staff member id.
AuthSessionContext authContextWithStaff({
  required String staffMemberId,
  bool setupRequired = false,
  bool isBootstrapAdmin = true,
}) {
  final base = sampleAuthSessionContext(setupRequired: setupRequired, isBootstrapAdmin: isBootstrapAdmin);
  return base.copyWith(
    staffProfile: StaffProfile(
      staffMemberId: staffMemberId,
      fullName: base.staffProfile.fullName,
      role: base.staffProfile.role,
      isBootstrapAdmin: isBootstrapAdmin,
      isActive: base.staffProfile.isActive,
    ),
  );
}

ClinicSetupState defaultTestClinicSetupState() {
  return ClinicSetupState(draft: createDefaultSetup());
}

List<Override> clinicSetupWelcomeScopeOverrides({
  required TestAuthSessionNotifier auth,
  ClinicSetupState? setupState,
  List<Override> extraOverrides = const [],
}) {
  final setup = setupState ?? defaultTestClinicSetupState();
  return [
    authSessionProvider.overrideWith(() => auth),
<<<<<<< HEAD
    clinicSetupProvider.overrideWith((ref) => TestClinicSetupNotifier(setup)),
=======
    clinicSetupProvider.overrideWith((ref) => TestClinicSetupNotifier(ref, setup)),
>>>>>>> master
    clinicSetupHydrationProvider.overrideWith((ref) async {}),
    ...extraOverrides,
  ];
}

Finder welcomeDialogTitleFinder() {
  return find.text('Welcome to ${ClinicSetupWelcomeDialog.appName}');
}

/// Pumps [ClinicSetupWelcomeScope] inside the canonical widget-test shell.
Future<void> pumpClinicSetupWelcomeScope(
  WidgetTester tester, {
  required TestAuthSessionNotifier auth,
  ClinicSetupState? setupState,
  List<Override> extraOverrides = const [],
  Size surfaceSize = const Size(800, 700),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: clinicSetupWelcomeScopeOverrides(
        auth: auth,
        setupState: setupState,
        extraOverrides: extraOverrides,
      ),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ClinicSetupWelcomeScope(
            child: const SizedBox(key: scopeChildSentinelKey),
          ),
        ),
      ),
    ),
  );
}

Future<void> pumpUntilWelcomeVisible(WidgetTester tester, {int maxFrames = 30}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (welcomeDialogTitleFinder().evaluate().isNotEmpty) {
      return;
    }
  }
  fail('Welcome dialog did not appear');
}

/// Dismisses the welcome dialog and exits any downstream setup / celebration dialogs.
Future<void> dismissActiveSetupWelcomeFlow(
  WidgetTester tester,
  TestAuthSessionNotifier auth,
) async {
<<<<<<< HEAD
=======
  auth.setAuthenticated(setupRequired: false);
  await tester.pump();

>>>>>>> master
  if (find.text('Continue').evaluate().isNotEmpty) {
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

<<<<<<< HEAD
  auth.setAuthenticated(setupRequired: false);
  await tester.pump();
=======
>>>>>>> master
  await tester.pump(const Duration(milliseconds: 200));

  if (find.text('Start exploring').evaluate().isNotEmpty) {
    await tester.tap(find.text('Start exploring'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> drainPendingFrames(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}
