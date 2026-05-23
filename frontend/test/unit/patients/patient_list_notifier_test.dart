import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/patients/data/patient_repository.dart';
import 'package:ai_clinic/features/patients/domain/patient_list_scope.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_notifier.dart';
import 'package:ai_clinic/features/patients/presentation/providers/patient_list_scope_provider.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/patient_rpc_test_client.dart';

AuthSessionState _authSession({
  Set<String> permissions = const {'patients.view'},
  String? activeBranchId = '44444444-4444-4444-8444-444444444444',
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(permissions: permissions, activeBranchId: activeBranchId),
  );
}

void main() {
  group('PatientListNotifier', () {
    late PatientRpcTestClient client;

    ProviderContainer container({AuthSessionState? auth}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _FixedAuth(auth ?? _authSession())),
          patientListScopeProvider.overrideWith(PatientListScopeNotifier.new),
          patientRepositoryProvider.overrideWith((ref) => PatientRepository(client)),
        ],
      );
    }

    setUp(() {
      client = PatientRpcTestClient();
    });

    test('loads patients on first read', () async {
      final c = container();
      addTearDown(c.dispose);

      final ui = await c.read(patientListProvider.future);

      expect(ui.items, hasLength(1));
      expect(client.lastFunction, 'search_patients');
      expect(client.lastParams?['p_scope'], 'branch');
    });

    test('short name query shows validation without RPC', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      client.lastFunction = null;

      await c.read(patientListProvider.notifier).reload(searchQuery: 'ab');

      final ui = c.read(patientListProvider).value!;
      expect(ui.validationHint, isNotNull);
      expect(ui.items, isEmpty);
      expect(client.lastFunction, isNull);
    });

    test('scope change triggers reload with organization scope', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      c.read(patientListScopeProvider.notifier).setScope(PatientListScope.allBranches);
      await c.read(patientListProvider.future);

      expect(client.lastParams?['p_scope'], 'organization');
      expect(client.lastParams?.containsKey('p_branch_id'), isFalse);
    });

    test('thisBranch without active branch fails with clear message', () async {
      final c = container(
        auth: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            permissions: const {'patients.view'},
            branchIds: const [],
            activeBranchId: null,
          ),
        ),
      );
      addTearDown(c.dispose);

      final future = c.read(patientListProvider.future);

      await expectLater(
        future,
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'Select an active branch before loading patients.'),
        ),
      );
      expect(client.lastFunction, isNull);
    });

    test('RPC failure maps to user-facing StateError', () async {
      client.rpcResults['search_patients'] = {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Denied'};

      final c = container();
      addTearDown(c.dispose);

      await expectLater(
        c.read(patientListProvider.future),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'You do not have permission to perform this action.'),
        ),
      );
    });

    test('loadMore appends next page', () async {
      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {
          'items': [
            {
              'id': '11111111-1111-4111-8111-111111111111',
              'full_name': 'Page One',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'branch_name': 'Main',
            },
          ],
          'total_count': 2,
          'limit': 1,
          'offset': 0,
        },
      };

      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);

      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {
          'items': [
            {
              'id': '22222222-2222-4222-8222-222222222222',
              'full_name': 'Page Two',
              'branch_id': '44444444-4444-4444-8444-444444444444',
              'branch_name': 'Main',
            },
          ],
          'total_count': 2,
          'limit': 1,
          'offset': 1,
        },
      };

      await c.read(patientListProvider.notifier).loadMore();

      final ui = c.read(patientListProvider).value!;
      expect(ui.items, hasLength(2));
      expect(ui.items.last.fullName, 'Page Two');
    });
  });
}

class _FixedAuth extends AuthSessionNotifier {
  _FixedAuth(this._initial);

  final AuthSessionState _initial;

  @override
  AuthSessionState build() => _initial;
}
