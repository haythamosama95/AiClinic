import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/global_status.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('ServiceEditorNotifier', () {
    test('createService calls RPCs and stores loaded detail', () async {
      final rpcClient = _ServiceCatalogRpcClient();
      final container = ProviderContainer(
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
          serviceCatalogRepositoryProvider.overrideWithValue(ServiceCatalogRepository(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final serviceId = await container
          .read(serviceEditorProvider(null).notifier)
          .createService(
            name: 'Consultation',
            defaultPrice: '200.00',
            globalStatus: GlobalStatus.active,
            assignAllBranches: false,
            selectedBranchIds: const {'branch-1', 'branch-2'},
          );

      expect(serviceId, 'service-1');
      expect(rpcClient.calls, ['create_service', 'get_service']);
      final state = container.read(serviceEditorProvider(null));
      expect(state.value?.detail?.service.name, 'Consultation');
    });
  });
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
          'branches': <dynamic>[],
        },
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
