import 'package:flutter/material.dart';
<<<<<<< HEAD
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/pages/clinic_management_page.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_management_notifier.dart';

void main() {
  testWidgets('ClinicManagementPage mounts without layout errors', (tester) async {
    const orgId = '20202020-2020-4020-8020-202020202020';
    final auth = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: AuthSessionContext(
        staffProfile: const StaffProfile(
          staffMemberId: '11111111-1111-4111-8111-111111111111',
          fullName: 'Admin User',
          role: StaffRole.administrator,
          isBootstrapAdmin: true,
          isActive: true,
        ),
        organizationId: orgId,
        branchIds: const ['44444444-4444-4444-8444-444444444444'],
        activeBranchId: '44444444-4444-4444-8444-444444444444',
        permissions: const {
          'settings.organization.manage',
          'settings.branches.manage',
          'settings.staff.manage',
          'settings.billing.manage',
        },
        setupRequired: false,
      ),
    );

    final state = ClinicManagementState(
      organization: const OrganizationProfile(
        id: orgId,
        name: 'Test Clinic',
        currencyCode: 'USD',
        timezone: 'America/New_York',
      ),
      branches: const [
        BranchListItem(id: '44444444-4444-4444-8444-444444444444', name: 'Main Branch', isActive: true, code: 'MAIN'),
      ],
      staff: const [
        StaffListItem(
          id: '22222222-2222-4222-8222-222222222222',
          fullName: 'Jane Doe',
          role: StaffRole.doctor,
          isActive: true,
          username: 'jane',
          branches: [
            StaffBranchLabel(id: '44444444-4444-4444-8444-444444444444', name: 'Main Branch', isPrimary: true),
          ],
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _AuthHarness(auth)),
          clinicManagementProvider.overrideWith(() => _ClinicHarness(state)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SingleChildScrollView(child: ClinicManagementPage())),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
=======
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';

import 'clinic_management/clinic_management_widget_test_harness.dart';

void main() {
  testWidgets('ClinicManagementPage mounts without layout errors', (tester) async {
    await pumpClinicManagementPage(tester);
    await pumpClinicManagementFrames(tester);
>>>>>>> master

    final exception = tester.takeException();
    expect(exception, isNull, reason: exception?.toString());

<<<<<<< HEAD
    // After skeleton minimum, content should render.
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
    expect(find.text('Clinic Management'), findsOneWidget);
  });
}

class _AuthHarness extends AuthSessionNotifier {
  _AuthHarness(this._state);

  final AuthSessionState _state;

  @override
  AuthSessionState build() => _state;
}

class _ClinicHarness extends ClinicManagementNotifier {
  _ClinicHarness(this._state);

  final ClinicManagementState _state;

  @override
  Future<ClinicManagementState> build() async => _state;
}
=======
    await pumpClinicManagementSkeletonTimer(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Clinic Management'), findsOneWidget);

    final tabs = tester.widget<AppTabs>(find.byType(AppTabs));
    expect(tabs.items, hasLength(6));
    expect(tabs.items.map((item) => item.label).toList(), [
      'Organization',
      'Branches',
      'Staff',
      'Roles',
      'Services',
      'Settings',
    ]);
  });

  testWidgets('ClinicManagementPage services tab scrolls in bounded viewport', (tester) async {
    final catalogState = buildServiceCatalogListState(
      items: [
        for (var index = 0; index < 12; index++)
          ServiceListItem(
            serviceId: '33333333-3333-4333-8333-${index.toString().padLeft(12, '0')}',
            name: 'Service $index',
            defaultPrice: Money.parse('150.00'),
            globalStatus: GlobalStatus.active,
            assignedBranchCount: 1,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
      ],
      total: 12,
    );

    await pumpClinicManagementPage(
      tester,
      overrides: clinicManagementProviderOverrides(
        clinicState: buildClinicManagementState(staff: const []),
        catalogState: catalogState,
      ),
      surfaceSize: const Size(1280, 554),
      scrollable: false,
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('Services'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('Service 0'), findsOneWidget);
    expect(find.text('Service 11'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
>>>>>>> master
