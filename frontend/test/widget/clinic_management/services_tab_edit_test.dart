import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/clinic-management/domain/branch_list_item.dart';
import 'package:ai_clinic/features/clinic-management/domain/organization_profile.dart';
import 'package:ai_clinic/features/clinic-management/presentation/components/services_tab.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  testWidgets('ServicesTab edit opens form after get_service completes', (tester) async {
    const orgId = '00000000-0000-4000-8000-000000000020';
    const serviceId = '33333333-3333-4333-8333-333333333333';
    const branchId = '44444444-4444-4444-8444-444444444444';

    final auth = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        branchIds: [branchId],
        activeBranchId: branchId,
        role: StaffRole.administrator,
        permissions: {'services.manage', 'services.view'},
      ),
    );

    final catalogState = ServiceCatalogListUiState(
      items: [
        ServiceListItem(
          serviceId: serviceId,
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

    final rpcClient = _ServiceCatalogRpcClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(auth)),
          serviceCatalogListProvider.overrideWith(() => _ServiceCatalogHarness(catalogState)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ServicesTab(
              branches: const [BranchListItem(id: branchId, name: 'Main Branch', isActive: true, code: 'MAIN')],
              organization: const OrganizationProfile(
                id: orgId,
                name: 'Test Clinic',
                currencyCode: 'USD',
                timezone: 'America/New_York',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Service actions').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit service'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Consultation')), findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.descendant(of: find.byType(Dialog), matching: find.text('Consultation')), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('ServicesTab delete confirms without provider disposal crash', (tester) async {
    const orgId = '00000000-0000-4000-8000-000000000020';
    const serviceId = '33333333-3333-4333-8333-333333333333';
    const branchId = '44444444-4444-4444-8444-444444444444';

    final auth = AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        branchIds: [branchId],
        activeBranchId: branchId,
        role: StaffRole.administrator,
        permissions: {'services.manage', 'services.view'},
      ),
    );

    final catalogState = ServiceCatalogListUiState(
      items: [
        ServiceListItem(
          serviceId: serviceId,
          name: 'Consultation',
          defaultPrice: Money.parse('150.00'),
          globalStatus: GlobalStatus.active,
          assignedBranchCount: 1,
          updatedAt: DateTime.utc(2026, 1, 2, 10),
        ),
        ServiceListItem(
          serviceId: '55555555-5555-4555-8555-555555555555',
          name: 'Follow-up',
          defaultPrice: Money.parse('75.00'),
          globalStatus: GlobalStatus.active,
          assignedBranchCount: 1,
          updatedAt: DateTime.utc(2026, 1, 2, 10),
        ),
      ],
      total: 2,
      filters: const ServiceListFilters(),
    );

    final rpcClient = _ServiceCatalogRpcClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(auth)),
          serviceCatalogListProvider.overrideWith(() => _ServiceCatalogHarness(catalogState)),
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ServicesTab(
              branches: const [BranchListItem(id: branchId, name: 'Main Branch', isActive: true, code: 'MAIN')],
              organization: const OrganizationProfile(
                id: orgId,
                name: 'Test Clinic',
                currencyCode: 'USD',
                timezone: 'America/New_York',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Service actions').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Remove service'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete service'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(rpcClient.calls, contains('soft_delete_service'));
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _ServiceCatalogHarness extends ServiceCatalogListNotifier {
  _ServiceCatalogHarness(this._state);

  final ServiceCatalogListUiState _state;

  @override
  Future<ServiceCatalogListUiState> build() async => _state;
}

class _ServiceCatalogRpcClient extends RpcCaptureSupabaseClient {
  final List<String> calls = <String>[];

  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    calls.add(fn);
    return FakePostgrestRpc(_payloadFor(fn)) as PostgrestFilterBuilder<T>;
  }

  Map<String, dynamic> _payloadFor(String fn) {
    return switch (fn) {
      'get_service' => {
        'success': true,
        'data': {
          'service': {
            'id': '33333333-3333-4333-8333-333333333333',
            'name': 'Consultation',
            'default_price': '150.00',
            'global_status': 'active',
            'created_at': '2026-01-01T10:00:00.000Z',
            'updated_at': '2026-01-02T10:00:00.000Z',
          },
          'branches': [
            {
              'service_branch_id': 'sb-1',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'status': 'active',
              'price_override': null,
              'promotion_price': null,
              'promotion_start_date': null,
              'promotion_end_date': null,
              'updated_at': '2026-01-01T10:00:00.000Z',
            },
          ],
        },
      },
      'soft_delete_service' => {
        'success': true,
        'data': {'service_id': '33333333-3333-4333-8333-333333333333'},
      },
      _ => {'success': true, 'data': <String, dynamic>{}},
    };
  }
}
