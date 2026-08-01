import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
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
import 'clinic_management_widget_test_harness.dart';

void main() {
  const orgId = '00000000-0000-4000-8000-000000000020';
  const branchId = '44444444-4444-4444-8444-444444444444';

  final branches = const [BranchListItem(id: branchId, name: 'Main Branch', isActive: true, code: 'MAIN')];
  final organization = const OrganizationProfile(
    id: orgId,
    name: 'Test Clinic',
    currencyCode: 'USD',
    timezone: 'America/New_York',
  );

  AuthSessionState adminAuth({Set<String> permissions = const {'services.manage', 'services.view'}}) {
    return AuthSessionState(
      status: AuthSessionStatus.authenticated,
      context: sampleAuthSessionContext(
        branchIds: [branchId],
        activeBranchId: branchId,
        role: StaffRole.administrator,
        permissions: permissions,
      ),
    );
  }

  Future<void> pumpServicesTab(
    WidgetTester tester, {
    required ServiceCatalogListNotifier catalogHarness,
    RpcCaptureSupabaseClient? rpcClient,
    AuthSessionState? auth,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(auth ?? adminAuth())),
          serviceCatalogListProvider.overrideWith(() => catalogHarness),
          if (rpcClient != null)
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: ServicesTab(branches: branches, organization: organization)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ServicesTab shows empty catalog panel', (tester) async {
    final harness = _StaticCatalogHarness(
      const ServiceCatalogListUiState(items: [], total: 0, filters: ServiceListFilters()),
    );

    await pumpServicesTab(tester, catalogHarness: harness);

    expect(find.text('No services yet'), findsOneWidget);
    expect(find.text('Add billable procedures to use when creating invoices.'), findsOneWidget);
    expect(find.text('Add service'), findsNWidgets(2));
  });

  testWidgets('ServicesTab shows catalog error and retries', (tester) async {
    final harness = _ErrorThenSuccessCatalogHarness();

    await pumpServicesTab(tester, catalogHarness: harness);

    expect(find.text('Unable to load services'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('No services yet'), findsOneWidget);
    expect(harness.reloadCount, 1);
  });

  testWidgets('ServicesTab shows no-results state and clears search', (tester) async {
    final harness = _FilterableCatalogHarness(
      allItems: [
        ServiceListItem(
          serviceId: '33333333-3333-4333-8333-333333333333',
          name: 'Consultation',
          defaultPrice: Money.parse('150.00'),
          globalStatus: GlobalStatus.active,
          assignedBranchCount: 1,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );

    await pumpServicesTab(tester, catalogHarness: harness);

    await tester.enterText(find.bySemanticsLabel('Search services'), 'missing');
    await tester.pumpAndSettle();

    expect(find.text('No services match'), findsOneWidget);
    expect(find.text('Clear search'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('Consultation'), findsOneWidget);
    expect(find.text('No services match'), findsNothing);
  });

  testWidgets('ServicesTab hides management actions without services.manage', (tester) async {
    final harness = _StaticCatalogHarness(
      const ServiceCatalogListUiState(items: [], total: 0, filters: ServiceListFilters()),
    );

    await pumpServicesTab(
      tester,
      catalogHarness: harness,
      auth: adminAuth(permissions: const {'services.view'}),
    );

    expect(find.text('No services yet'), findsOneWidget);
    expect(find.text('Add service'), findsNothing);
    expect(find.bySemanticsLabel('Service actions'), findsNothing);
  });

  testWidgets('ServicesTab create service flow submits new service', (tester) async {
    final harness = _ReloadNoopCatalogHarness(
      const ServiceCatalogListUiState(items: [], total: 0, filters: ServiceListFilters()),
    );
    final rpcClient = _ServiceCatalogRpcClient();

    await tester.binding.setSurfaceSize(clinicMgmtWideSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpServicesTab(tester, catalogHarness: harness, rpcClient: rpcClient);

    await tester.tap(find.widgetWithText(AppButton, 'Add service').first);
    await settleClinicMgmtWidget(tester);

    expect(find.byType(Dialog), findsOneWidget);

    await tester.tap(clinicMgmtEditableText('new-service-name'));
    await tester.enterText(clinicMgmtEditableText('new-service-name'), 'Dental cleaning');
    await tester.tap(clinicMgmtEditableText('new-service-price'));
    await tester.pump();
    await tester.enterText(clinicMgmtEditableText('new-service-price'), '99');
    await tester.pump();
    await tester.tap(find.text('Service name'));
    await settleClinicMgmtWidget(tester);

    await tester.tap(find.text('Add service').last);
    await settleClinicMgmtWidget(tester);

    expect(rpcClient.calls, contains('create_service'));
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _StaticCatalogHarness extends ServiceCatalogListNotifier {
  _StaticCatalogHarness(this._state);

  final ServiceCatalogListUiState _state;

  @override
  Future<ServiceCatalogListUiState> build() async => _state;
}

class _ReloadNoopCatalogHarness extends _StaticCatalogHarness {
  _ReloadNoopCatalogHarness(super.state);

  @override
  Future<void> reload() async {}
}

class _ErrorThenSuccessCatalogHarness extends ServiceCatalogListNotifier {
  var loadCount = 0;
  var reloadCount = 0;

  @override
  Future<ServiceCatalogListUiState> build() async => _load();

  @override
  Future<void> reload() async {
    reloadCount++;
    state = await AsyncValue.guard(_load);
  }

  Future<ServiceCatalogListUiState> _load() async {
    loadCount++;
    if (loadCount == 1) {
      throw StateError('catalog failed');
    }
    return const ServiceCatalogListUiState(items: [], total: 0, filters: ServiceListFilters());
  }
}

class _FilterableCatalogHarness extends ServiceCatalogListNotifier {
  _FilterableCatalogHarness({required this.allItems});

  final List<ServiceListItem> allItems;
  ServiceListFilters _filters = const ServiceListFilters();

  @override
  Future<ServiceCatalogListUiState> build() async => _stateFor(_filters);

  @override
  Future<void> applyFilters(ServiceListFilters filters) async {
    _filters = filters;
    state = await AsyncValue.guard(() async => _stateFor(filters));
  }

  ServiceCatalogListUiState _stateFor(ServiceListFilters filters) {
    final query = filters.query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allItems
        : allItems.where((item) => item.name.toLowerCase().contains(query)).toList();
    return ServiceCatalogListUiState(items: filtered, total: allItems.length, filters: filters);
  }
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
      'create_service' => {
        'success': true,
        'data': {
          'service_id': '55555555-5555-4555-8555-555555555555',
          'assigned_branch_ids': ['44444444-4444-4444-8444-444444444444'],
        },
      },
      'get_service' => {
        'success': true,
        'data': {
          'service': {
            'id': '55555555-5555-4555-8555-555555555555',
            'name': 'Dental cleaning',
            'default_price': '99.00',
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
      _ => {'success': true, 'data': <String, dynamic>{}},
    };
  }
}
