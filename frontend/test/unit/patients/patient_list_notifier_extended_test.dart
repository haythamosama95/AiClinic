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
  group('PatientListNotifier extended', () {
    late PatientRpcTestClient client;

    ProviderContainer container({AuthSessionState? auth}) {
      return ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(() => _FixedAuth(auth ?? _authSession())),
          patientListScopeProvider.overrideWith(PatientListScopeNotifier.new),
          patientRepositoryProvider.overrideWith((ref) => PatientRepositoryImpl(client)),
        ],
      );
    }

    setUp(() {
      client = PatientRpcTestClient();
    });

    test('reload with valid name query sends to RPC', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      await c.read(patientListProvider.notifier).reload(searchQuery: 'ahmed');

      final ui = c.read(patientListProvider).value!;
      expect(ui.searchQuery, 'ahmed');
      expect(ui.validationHint, isNull);
      expect(client.lastParams?['p_query'], 'ahmed');
    });

    test('reload with valid phone query sends to RPC', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      await c.read(patientListProvider.notifier).reload(searchQuery: '2010');

      final ui = c.read(patientListProvider).value!;
      expect(ui.searchQuery, '2010');
      expect(ui.validationHint, isNull);
    });

    test('reload clears previous results when query becomes invalid', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      expect(c.read(patientListProvider).value!.items, isNotEmpty);

      await c.read(patientListProvider.notifier).reload(searchQuery: 'ab');
      final ui = c.read(patientListProvider).value!;
      expect(ui.items, isEmpty);
      expect(ui.validationHint, isNotNull);
    });

    test('reload with empty string clears search and fetches browse results', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      await c.read(patientListProvider.notifier).reload(searchQuery: 'ahmed');
      await c.read(patientListProvider.notifier).reload(searchQuery: '');

      final ui = c.read(patientListProvider).value!;
      expect(ui.searchQuery, '');
      expect(ui.validationHint, isNull);
    });

    test('loadMore does nothing when no more items', () async {
      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {
          'items': [
            {'id': 'p1', 'full_name': 'Only', 'branch_id': 'b1', 'branch_name': 'Main'},
          ],
          'total_count': 1,
          'limit': 25,
          'offset': 0,
        },
      };

      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);

      final beforeFunction = client.lastFunction;
      client.lastFunction = null;

      await c.read(patientListProvider.notifier).loadMore();

      expect(client.lastFunction, isNull, reason: 'should not call RPC when no more items');
      expect(c.read(patientListProvider).value!.items, hasLength(1));
    });

    test('loadMore does nothing when validationHint is present', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      await c.read(patientListProvider.notifier).reload(searchQuery: 'ab');

      client.lastFunction = null;
      await c.read(patientListProvider.notifier).loadMore();

      expect(client.lastFunction, isNull);
    });

    test('reload trims whitespace from query', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);
      await c.read(patientListProvider.notifier).reload(searchQuery: '  ahmed  ');

      final ui = c.read(patientListProvider).value!;
      expect(ui.searchQuery, 'ahmed');
    });

    test('loadMore error transitions state to AsyncError', () async {
      client.rpcResults['search_patients'] = {
        'success': true,
        'data': {
          'items': [
            {'id': 'p1', 'full_name': 'First', 'branch_id': 'b1', 'branch_name': 'Main'},
          ],
          'total_count': 50,
          'limit': 1,
          'offset': 0,
        },
      };

      final c = container();
      addTearDown(c.dispose);

      await c.read(patientListProvider.future);

      client.rpcResults['search_patients'] = {
        'success': false,
        'error_code': 'FORBIDDEN',
        'error_message': 'Denied',
      };

      await c.read(patientListProvider.notifier).loadMore();

      expect(c.read(patientListProvider).hasError, isTrue);
    });

    test('organization scope does not require active branch id', () async {
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

      c.read(patientListScopeProvider.notifier).setScope(PatientListScope.allBranches);
      final ui = await c.read(patientListProvider.future);

      expect(ui.items, isNotEmpty);
      expect(client.lastParams?['p_scope'], 'organization');
    });

    test('pageSize constant is 25', () {
      expect(PatientListNotifier.pageSize, 25);
    });
  });
}

class _FixedAuth extends AuthSessionNotifier {
  _FixedAuth(this._initial);

  final AuthSessionState _initial;

  @override
  AuthSessionState build() => _initial;
}
