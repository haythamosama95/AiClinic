import 'package:flutter/material.dart';
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

    final exception = tester.takeException();
    expect(exception, isNull, reason: exception?.toString());

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
