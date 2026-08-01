import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/domain/permission_keys.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../helpers/role_permission_seed.dart';
import '../../support/visit_encounter_test_support.dart';
import '../../support/visit_rpc_test_client.dart';

const _visitIdA = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _visitIdB = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
const _otherBranchId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> _visitRpcData({
  required String visitId,
  String? branchId,
  String? patientId,
}) {
  return {
    'success': true,
    'data': {
      'id': visitId,
      'branch_id': branchId ?? encounterTestBranchId,
      'appointment_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'patient_id': patientId ?? encounterTestPatientId,
      'doctor_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
      'doctor_name': 'Dr Test',
      'visit_date': '2026-05-31',
      'status': 'in_progress',
      'documentation': {
        'complaint': 'Headache',
        'history': null,
        'examination': null,
        'diagnosis': null,
        'plan': null,
        'updated_at': '2026-05-31T10:00:00.000Z',
      },
    },
  };
}

ProviderContainer _createContainer({
  required VisitRpcTestClient client,
  required AuthSessionState authState,
}) {
  final container = ProviderContainer(
    overrides: [
      authSessionProvider.overrideWith(() => _PresetAuthSessionNotifier(authState)),
      visitRepositoryProvider.overrideWith((ref) => VisitRepository(client)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

AuthSessionState _authenticated({
  List<String> branchIds = const [encounterTestBranchId],
  Set<String> permissions = RolePermissionSeed.doctor,
}) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext(
      branchIds: branchIds,
      activeBranchId: branchIds.isEmpty ? null : branchIds.first,
      permissions: permissions,
    ),
  );
}

void main() {
  group('visitDetailViewProvider', () {
    late VisitRpcTestClient client;

    setUp(() {
      client = VisitRpcTestClient(
        rpcResults: {
          'get_visit': _visitRpcData(visitId: _visitIdA),
        },
      );
    });

    test('trivial: successful fetch maps RPC into VisitDetailViewState', () async {
      final container = _createContainer(client: client, authState: _authenticated());
      final transitions = <AsyncValue<VisitDetailViewState>>[];
<<<<<<< HEAD
      container.listen(visitDetailViewProvider(_visitIdA), transitions.add, fireImmediately: true);
=======
      container.listen(visitDetailViewProvider(_visitIdA), (_, next) => transitions.add(next), fireImmediately: true);
>>>>>>> master

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.visit.id, _visitIdA);
      expect(view.visit.branchId, encounterTestBranchId);
      expect(view.visit.status, VisitStatus.inProgress);
      expect(view.visit.documentation?.complaint, 'Headache');
      expect(client.paramsForFunction('get_visit')?['p_visit_id'], _visitIdA);
      expect(transitions.last, isA<AsyncData<VisitDetailViewState>>());
    });

    test('trivial: doctor with branch access receives all permission flags', () async {
      final container = _createContainer(
        client: client,
        authState: _authenticated(permissions: RolePermissionSeed.doctor),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.hasBranchAccess, isTrue);
      expect(view.canEditDocumentation, isTrue);
      expect(view.canUploadAttachments, isTrue);
    });

    test('advanced: canEditDocumentation false without visits.edit_soap', () async {
      final container = _createContainer(
        client: client,
        authState: _authenticated(
          permissions: {PermissionKeys.visitsCreate, PermissionKeys.visitsUploadAttachment},
        ),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.hasBranchAccess, isTrue);
      expect(view.canEditDocumentation, isFalse);
      expect(view.canUploadAttachments, isTrue);
    });

    test('advanced: canUploadAttachments false for receptionist without upload keys', () async {
      final container = _createContainer(
        client: client,
        authState: _authenticated(permissions: RolePermissionSeed.receptionist),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.hasBranchAccess, isTrue);
      expect(view.canEditDocumentation, isFalse);
      expect(view.canUploadAttachments, isFalse);
    });

    test('advanced: lab staff may upload but cannot edit documentation', () async {
      final container = _createContainer(
        client: client,
        authState: _authenticated(permissions: RolePermissionSeed.labStaff),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.canEditDocumentation, isFalse);
      expect(view.canUploadAttachments, isTrue);
    });

    test('invalid state: visit in inaccessible branch denies branch-derived flags', () async {
      client.rpcResults['get_visit'] = _visitRpcData(visitId: _visitIdA, branchId: _otherBranchId);
      final container = _createContainer(
        client: client,
        authState: _authenticated(permissions: RolePermissionSeed.administrator),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.hasBranchAccess, isFalse);
      expect(view.canEditDocumentation, isFalse);
      expect(view.canUploadAttachments, isFalse);
    });

    test('invalid state: empty branch assignment denies all permission flags', () async {
      final container = _createContainer(
        client: client,
        authState: _authenticated(branchIds: const [], permissions: RolePermissionSeed.administrator),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);

      expect(view.hasBranchAccess, isFalse);
      expect(view.canEditDocumentation, isFalse);
      expect(view.canUploadAttachments, isFalse);
    });

    test('invalid state: RPC failure propagates as AsyncError with code', () async {
      client.rpcResults['get_visit'] = {
        'success': false,
        'error_code': 'RPC_ERROR',
        'error_message': 'Service unavailable',
      };
      final container = _createContainer(client: client, authState: _authenticated());
<<<<<<< HEAD
      final transitions = <AsyncValue<VisitDetailViewState>>[];
      container.listen(visitDetailViewProvider(_visitIdA), transitions.add, fireImmediately: true);

      await expectLater(
        container.read(visitDetailViewProvider(_visitIdA).future),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_ERROR')),
      );
      expect(transitions.any((value) => value is AsyncLoading), isTrue);
      expect(container.read(visitDetailViewProvider(_visitIdA)), isA<AsyncError>());
=======
      final provider = visitDetailViewProvider(_visitIdA);
      final transitions = <AsyncValue<VisitDetailViewState>>[];
      final subscription = container.listen(provider, (_, next) => transitions.add(next), fireImmediately: true);
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<RpcFailure>().having((e) => e.code, 'code', 'RPC_ERROR'),
      );
      expect(transitions.any((value) => value is AsyncLoading), isTrue);
>>>>>>> master
    });

    test('regression: NOT_FOUND propagates from get_visit', () async {
      client.rpcResults['get_visit'] = {
        'success': false,
        'error_code': 'NOT_FOUND',
        'error_message': 'Missing',
      };
      final container = _createContainer(client: client, authState: _authenticated());
<<<<<<< HEAD

      await expectLater(
        container.read(visitDetailViewProvider(_visitIdA).future),
        throwsA(isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND')),
=======
      final provider = visitDetailViewProvider(_visitIdA);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      container.read(provider);
      await pumpEventQueue();

      final asyncValue = container.read(provider);
      expect(asyncValue.hasError, isTrue);
      expect(
        asyncValue.error,
        isA<RpcFailure>().having((e) => e.code, 'code', 'NOT_FOUND'),
>>>>>>> master
      );
    });

    test('stupid usage: blank visit id throws before RPC', () async {
      final container = _createContainer(client: client, authState: _authenticated());

      await expectLater(
        container.read(visitDetailViewProvider('   ').future),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'Visit id is required.')),
      );
      expect(client.rpcLog, isEmpty);
    });

    test('edge case: two visit ids resolve independently', () async {
      client.rpcResults['get_visit'] = _visitRpcData(visitId: _visitIdA);
      final container = _createContainer(client: client, authState: _authenticated());

      await container.read(visitDetailViewProvider(_visitIdA).future);

      client.rpcResults['get_visit'] = _visitRpcData(
        visitId: _visitIdB,
        patientId: '22222222-2222-4222-8222-222222222222',
      );

      final viewB = await container.read(visitDetailViewProvider(_visitIdB).future);
      final viewA = container.read(visitDetailViewProvider(_visitIdA)).requireValue;

      expect(viewA.visit.id, _visitIdA);
      expect(viewB.visit.id, _visitIdB);
      expect(viewB.visit.patientId, '22222222-2222-4222-8222-222222222222');
    });
  });

  group('visitDetailProvider', () {
    test('trivial: deprecated wrapper returns the same VisitDetail as visitDetailViewProvider', () async {
      final client = VisitRpcTestClient(
        rpcResults: {'get_visit': _visitRpcData(visitId: _visitIdA)},
      );
      final container = _createContainer(
        client: client,
        authState: AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: sampleAuthSessionContext(
            branchIds: [encounterTestBranchId],
            permissions: RolePermissionSeed.doctor,
          ),
        ),
      );

      final view = await container.read(visitDetailViewProvider(_visitIdA).future);
      final detail = await container.read(visitDetailProvider(_visitIdA).future);

      expect(detail, view.visit);
      expect(client.rpcCalls.where((call) => call.fn == 'get_visit').length, 1);
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
