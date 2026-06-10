import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/features/setup/presentation/widgets/setup_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';

const setupSurfaceSize = Size(920, 900);
const setupNarrowSurfaceSize = Size(320, 640);

AuthSessionContext bootstrapAdminSessionContext({bool setupRequired = true, bool hasShownPasswordWarning = false}) {
  return AuthSessionContext(
    staffProfile: const StaffProfile(
      staffMemberId: '00000000-0000-4000-8000-000000000010',
      fullName: 'Bootstrap Admin',
      role: StaffRole.administrator,
      isBootstrapAdmin: true,
      isActive: true,
    ),
    organizationId: setupRequired ? null : '00000000-0000-4000-8000-000000000020',
    branchIds: const [],
    activeBranchId: null,
    permissions: const {},
    setupRequired: setupRequired,
  );
}

class SetupTestAuthSessionNotifier extends TestAuthSessionNotifier {
  var refreshSessionContextCount = 0;

  @override
  Future<void> refreshSessionContext() async {
    refreshSessionContextCount++;
  }
}

class BootstrapAdminAuthSessionNotifier extends SetupTestAuthSessionNotifier {
  @override
  AuthSessionState build() {
    return AuthSessionState(status: AuthSessionStatus.authenticated, context: bootstrapAdminSessionContext());
  }
}

Future<ProviderContainer> pumpSetupModal(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = setupSurfaceSize,
  VoidCallback? onFinished,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authSessionProvider.overrideWith(SetupTestAuthSessionNotifier.new), ...overrides],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
        home: Scaffold(body: SetupModal(onFinished: onFinished ?? () {})),
      ),
    ),
  );
  await tester.pumpAndSettle();
  container = ProviderScope.containerOf(tester.element(find.byType(SetupModal)));
  return container;
}

Future<void> enterOrganizationBasics(WidgetTester tester, {String name = 'Sunrise Clinic'}) async {
  await tester.enterText(find.widgetWithText(AppTextField, 'Organization name *'), name);
  await tester.pump();
}

Future<void> tapSetupNext(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, 'Next'));
  await tester.pumpAndSettle();
}

Future<void> tapSetupFinish(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, 'Finish'));
  await tester.pumpAndSettle();
}

Future<void> tapSetupBack(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(AppButton, 'Back'));
  await tester.pumpAndSettle();
}

Future<void> advanceSetupModalToBranch(WidgetTester tester, {String orgName = 'Sunrise Clinic'}) async {
  await enterOrganizationBasics(tester, name: orgName);
  await tapSetupNext(tester);
}

Future<void> advanceSetupModalToStaff(
  WidgetTester tester, {
  String orgName = 'Sunrise Clinic',
  String branchName = 'Main Branch',
  String branchCode = 'MAIN',
  String address = '123 Street',
  String phone = '201000000000',
  String mapsUrl = 'https://maps.example.com/main',
}) async {
  await advanceSetupModalToBranch(tester, orgName: orgName);
  await tester.enterText(find.widgetWithText(AppTextField, 'Branch name *'), branchName);
  await tester.enterText(find.widgetWithText(AppTextField, 'Branch code *'), branchCode);
  await tester.enterText(find.widgetWithText(AppTextField, 'Address *'), address);
  await tester.enterText(find.widgetWithText(AppTextField, 'Phone *'), phone);
  await tester.enterText(find.widgetWithText(AppTextField, 'Maps URL *'), mapsUrl);
  await tester.pump();
  await tapSetupNext(tester);
}

Future<void> addStaffDraftViaForm(
  WidgetTester tester, {
  String fullName = 'Front Desk',
  String phone = '201000000001',
  String username = 'frontdesk',
  String password = 'Secret12',
}) async {
  await tester.enterText(find.widgetWithText(AppTextField, 'Full name *'), fullName);
  await tester.enterText(find.widgetWithText(AppTextField, 'Phone number *'), phone);
  await tester.enterText(find.widgetWithText(AppTextField, 'Username *'), username);
  await tester.enterText(find.widgetWithText(AppTextField, 'Initial password *'), password);
  await tester.pump();
  await tester.tap(find.widgetWithText(AppButton, 'Create staff account'));
  await tester.pumpAndSettle();
}

void setBootstrapAdminSession(ProviderContainer container, {bool hasShownPasswordWarning = false}) {
  final notifier = container.read(authSessionProvider.notifier) as SetupTestAuthSessionNotifier;
  notifier.setSession(
    AuthSessionState(status: AuthSessionStatus.authenticated, context: bootstrapAdminSessionContext()),
  );
  if (hasShownPasswordWarning) {
    container.read(setupNotifierProvider.notifier).markPasswordWarningShown();
  }
}

void setAdministratorSession(ProviderContainer container, {bool setupRequired = true}) {
  final notifier = container.read(authSessionProvider.notifier) as SetupTestAuthSessionNotifier;
  notifier.setSession(
    AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(setupRequired: setupRequired),
    ),
  );
}
