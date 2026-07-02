import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/app_theme.dart';
import 'package:ai_clinic/core/ui/theme/forui_app_scope.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/create_service_modal.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/providers/clinic_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('CreateServiceModal', () {
    Future<void> pumpWithModal(WidgetTester tester, {RpcCaptureSupabaseClient? rpcClient}) async {
      final client = rpcClient ?? _CreateServiceRpcClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSessionProvider.overrideWith(
              () => _PresetAuthSessionNotifier(
                AuthSessionState(
                  status: AuthSessionStatus.authenticated,
                  context: sampleAuthSessionContext(
                    role: StaffRole.administrator,
                    permissions: {'services.manage', 'services.view'},
                  ),
                ),
              ),
            ),
            serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(client)),
            clinicSetupBranchesProvider.overrideWith(
              (ref) async => const [
                BranchListItem(id: 'branch-1', name: 'Branch A', code: 'BA', isActive: true),
                BranchListItem(id: 'branch-2', name: 'Branch B', code: 'BB', isActive: true),
              ],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => ForuiAppScope(child: child ?? const SizedBox.shrink()),
            home: Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: AppButton(label: 'Open', onPressed: () => CreateServiceModal.show(context)),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Future<void> fillValidServiceForm(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(AppTextField, 'Service name'), 'Consultation');
      await tester.enterText(find.widgetWithText(AppTextField, 'Price'), '200.00');
    }

    testWidgets('dismiss on scrim tap', (tester) async {
      await pumpWithModal(tester);

      expect(find.text('Add service'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Add service'), findsNothing);
    });

    Future<void> tapSaveService(WidgetTester tester) async {
      final saveButton = find.widgetWithText(AppButton, 'Save service');
      await tester.scrollUntilVisible(saveButton, 48, scrollable: find.byType(Scrollable).last);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
    }

    testWidgets('validates required fields', (tester) async {
      final rpcClient = _CreateServiceRpcClient();
      await pumpWithModal(tester, rpcClient: rpcClient);

      await tapSaveService(tester);

      expect(rpcClient.lastFunction, isNull);
      expect(find.text('Service name'), findsOneWidget);
    });

    testWidgets('create success closes modal and calls RPC', (tester) async {
      final rpcClient = _CreateServiceRpcClient();
      await pumpWithModal(tester, rpcClient: rpcClient);
      await fillValidServiceForm(tester);

      await tapSaveService(tester);

      expect(rpcClient.calls, contains('create_service'));
      expect(find.text('Add service'), findsNothing);
    });

    testWidgets('shows sectioned layout while creating', (tester) async {
      await pumpWithModal(tester);
      await fillValidServiceForm(tester);
      await tester.pumpAndSettle();

      expect(find.text('Service info'), findsOneWidget);
      expect(find.text('Branch configuration'), findsOneWidget);
      expect(find.text('Per branch configuration'), findsOneWidget);
      expect(find.text('Apply this service to'), findsOneWidget);
      expect(find.text('Assign to all branches'), findsOneWidget);
      expect(find.text('Global status'), findsOneWidget);
    });

    testWidgets('keyboard Enter submits modal', (tester) async {
      final rpcClient = _CreateServiceRpcClient();
      await pumpWithModal(tester, rpcClient: rpcClient);
      await fillValidServiceForm(tester);

      await tester.tap(find.widgetWithText(AppTextField, 'Service name'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(rpcClient.calls, contains('create_service'));
      expect(find.text('Add service'), findsNothing);
    });
  });
}

class _CreateServiceRpcClient extends RpcCaptureSupabaseClient {
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
          'service_id': 'service-1',
          'assigned_branch_ids': ['branch-1', 'branch-2'],
        },
      },
      'get_service' => {
        'success': true,
        'data': {
          'service': {
            'id': 'service-1',
            'name': 'Consultation',
            'default_price': '200.00',
            'global_status': 'active',
            'created_at': '2026-01-01T10:00:00.000Z',
            'updated_at': '2026-01-01T10:00:00.000Z',
          },
          'branches': [
            {
              'service_branch_id': 'sb-1',
              'branch_id': 'branch-1',
              'status': 'active',
              'price_override': null,
              'promotion_price': null,
              'promotion_start_date': null,
              'promotion_end_date': null,
              'updated_at': '2026-01-01T10:00:00.000Z',
            },
            {
              'service_branch_id': 'sb-2',
              'branch_id': 'branch-2',
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
      'configure_service_branch' => {
        'success': true,
        'data': {'service_branch_id': 'sb-1', 'updated_at': '2026-01-02T10:00:00.000Z'},
      },
      'set_service_promotion' => {
        'success': true,
        'data': {'service_branch_id': 'sb-1', 'has_promotion': true, 'updated_at': '2026-01-03T10:00:00.000Z'},
      },
      _ => {'success': true, 'data': <String, dynamic>{}},
    };
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
