import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/components/app_tabs.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/domain/billing_settings.dart';
import 'package:ai_clinic/features/billing/presentation/providers/billing_settings_notifier.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/domain/staff_list_item.dart';
import 'package:ai_clinic/features/clinic-management/presentation/pages/clinic_management_page.dart';
import 'package:ai_clinic/features/clinic-management/presentation/providers/clinic_management_notifier.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';

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
          'settings.manage_branches',
          'settings.manage_staff',
          'services.view',
          'services.manage',
          'invoices.view',
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

    final catalogState = ServiceCatalogListUiState(
      items: [
        ServiceListItem(
          serviceId: '33333333-3333-4333-8333-333333333333',
          name: 'Consultation',
          defaultPrice: Money.parse('150.00'),
          globalStatus: GlobalStatus.active,
          assignedBranchCount: 1,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
      total: 1,
      filters: const ServiceListFilters(),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 900));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _AuthHarness(auth)),
          clinicManagementProvider.overrideWith(() => _ClinicHarness(state)),
          serviceCatalogListProvider.overrideWith(() => _ServiceCatalogHarness(catalogState)),
          billingSettingsProvider.overrideWith(() => _BillingSettingsHarness(const BillingSettings(allowPartialPayments: false))),
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
          'settings.manage_branches',
          'settings.manage_staff',
          'services.view',
          'services.manage',
          'invoices.view',
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
      staff: const [],
    );

    final catalogState = ServiceCatalogListUiState(
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
      filters: const ServiceListFilters(),
    );

    await tester.binding.setSurfaceSize(const Size(1280, 554));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _AuthHarness(auth)),
          clinicManagementProvider.overrideWith(() => _ClinicHarness(state)),
          serviceCatalogListProvider.overrideWith(() => _ServiceCatalogHarness(catalogState)),
          billingSettingsProvider.overrideWith(() => _BillingSettingsHarness(const BillingSettings(allowPartialPayments: false))),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: ClinicManagementPage()),
        ),
      ),
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

class _ServiceCatalogHarness extends ServiceCatalogListNotifier {
  _ServiceCatalogHarness(this._state);

  final ServiceCatalogListUiState _state;

  @override
  Future<ServiceCatalogListUiState> build() async => _state;
}

class _BillingSettingsHarness extends BillingSettingsNotifier {
  _BillingSettingsHarness(this._state);

  final BillingSettings _state;

  @override
  Future<BillingSettings> build() async => _state;
}
