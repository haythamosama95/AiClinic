import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_list_item.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_list_filters.dart';
import 'package:ai_clinic/features/service_catalog/presentation/pages/service_catalog_list_page.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_catalog_list_notifier.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('ServiceCatalogListPage', () {
    testWidgets('shows permission denied without catalog access', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(role: StaffRole.receptionist, permissions: const {}),
                ),
              ),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const ServiceCatalogListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('You do not have permission to view the service catalog.'), findsOneWidget);
    });

    testWidgets('shows loading then results for authorized users', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
                ),
              ),
            ),
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(_ListPageRpcClient())),
            clinicSetupBranchesProvider.overrideWith(
              (ref) async => const [BranchListItem(id: 'branch-1', name: 'Branch A', code: 'BA', isActive: true)],
            ),
            serviceCatalogListProvider.overrideWith(() => _LoadedListNotifier()),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const ServiceCatalogListPage()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('No services match your filters.'), findsNothing);
    });

    testWidgets('shows empty state when list has no items', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(role: StaffRole.administrator, permissions: {'services.view'}),
                ),
              ),
            ),
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(_ListPageRpcClient())),
            clinicSetupBranchesProvider.overrideWith((ref) async => const <BranchListItem>[]),
            serviceCatalogListProvider.overrideWith(() => _EmptyListNotifier()),
          ],
          child: MaterialApp(theme: AppTheme.light(), home: const ServiceCatalogListPage()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No services match your filters.'), findsOneWidget);
    });
  });
}

class _LoadedListNotifier extends ServiceCatalogListNotifier {
  @override
  Future<ServiceCatalogListUiState> build() async {
    return ServiceCatalogListUiState(
      items: [
        ServiceListItem(
          serviceId: 'service-1',
          name: 'Consultation',
          defaultPrice: Money.parse('200.00'),
          globalStatus: GlobalStatus.active,
          assignedBranchCount: 1,
          updatedAt: DateTime.parse('2026-01-01T10:00:00.000Z'),
        ),
      ],
      total: 1,
      filters: const ServiceListFilters(),
    );
  }
}

class _EmptyListNotifier extends ServiceCatalogListNotifier {
  @override
  Future<ServiceCatalogListUiState> build() async {
    return const ServiceCatalogListUiState(items: [], total: 0, filters: ServiceListFilters());
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _ListPageRpcClient extends RpcCaptureSupabaseClient {
  @override
  PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, dynamic get = false}) {
    return FakePostgrestRpc({
          'success': true,
          'data': {
            'total': 1,
            'items': [
              {
                'service_id': 'service-1',
                'name': 'Consultation',
                'default_price': '200.00',
                'global_status': 'active',
                'assigned_branch_count': 1,
                'updated_at': '2026-01-01T10:00:00.000Z',
              },
            ],
          },
        })
        as PostgrestFilterBuilder<T>;
  }
}
