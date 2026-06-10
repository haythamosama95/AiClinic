import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/setup/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_dummy_data.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_input.dart';
import 'package:ai_clinic/features/setup/domain/bootstrap_finish_setup_result.dart';
import 'package:ai_clinic/features/setup/presentation/providers/setup_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import '../../helpers/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('setupMessageForRpc', () {
    test('maps known setup error codes', () {
      expect(
        setupMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'ORG_ALREADY_EXISTS'}))),
        contains('already exists'),
      );

      expect(
        setupMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'NOT_BOOTSTRAP_ADMIN'}))),
        contains('bootstrap administrator'),
      );
    });

    test('falls back for unknown codes', () {
      expect(
        setupMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'UNKNOWN'}))),
        contains('Unable to save'),
      );
    });

    test('maps RESET_SAFE_DELETE to migration hint', () {
      expect(
        setupMessageForRpc(
          RpcFailure(
            RpcResult.fromDynamic({
              'success': false,
              'error_code': 'RESET_SAFE_DELETE',
              'error_message': 'Apply migration 20260521150000.',
            }),
          ),
        ),
        contains('20260521150000'),
      );
    });
  });

  group('SetupNotifier', () {
    test('continueToBranchStep stores draft without organizationId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.branch);
      expect(state.organizationId, isNull);
      expect(state.organizationDraft?.name, 'Sunrise Clinic');
    });

    test('continueToBranchStep rejects invalid currency', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'NOTREAL', timezone: 'Africa/Cairo');

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).step, SetupWizardStep.organization);
    });

    test('continueToStaffStep stores branch draft without organizationId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      final ok = notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '+20 100 000 0000',
        mapsUrl: 'https://maps.example.com/main',
      );

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.staff);
      expect(state.organizationId, isNull);
      expect(state.branchId, isNull);
      expect(state.branchDraft?.name, 'Main');
    });

    test('addStaffDraft stores staff locally without RPC', () {
      final container = ProviderContainer(overrides: [authSessionProvider.overrideWith(TestAuthSessionNotifier.new)]);
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setSession(
        AuthSessionState(
          status: AuthSessionStatus.authenticated,
          context: AuthSessionContext(
            staffProfile: const StaffProfile(
              staffMemberId: '00000000-0000-4000-8000-000000000010',
              fullName: 'Bootstrap Admin',
              role: StaffRole.administrator,
              isBootstrapAdmin: true,
              isActive: true,
            ),
            organizationId: null,
            branchIds: const [],
            activeBranchId: null,
            permissions: const {},
            setupRequired: true,
          ),
        ),
      );
      final notifier = container.read(setupNotifierProvider.notifier);

      notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');
      notifier.continueToStaffStep(
        branchName: 'Main',
        branchCode: 'MAIN',
        address: '123 Street',
        phone: '+20 100 000 0000',
        mapsUrl: 'https://maps.example.com/main',
      );

      final ok = notifier.addStaffDraft(
        username: 'owner1',
        fullName: 'Owner One',
        role: StaffRole.administrator,
        branchIds: const ['branch-local'],
        password: 'Secret12',
      );

      expect(ok, isTrue);
      expect(container.read(setupNotifierProvider).staffDrafts, hasLength(1));
      expect(container.read(setupNotifierProvider).staffDrafts.first.username, 'owner1');
    });

    test('finishSetupWithDummyData submits organization, branch, and staff atomically', () async {
      final bootstrapRepo = _RecordingBootstrapRepository();
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWithValue(bootstrapRepo),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);
      (container.read(authSessionProvider.notifier) as TestAuthSessionNotifier).setAuthenticated(setupRequired: true);

      final ok = await container.read(setupNotifierProvider.notifier).finishSetupWithDummyData();

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.complete);
      expect(state.organizationId, 'org-dummy');
      expect(state.branchId, 'branch-dummy');
      expect(state.staffDrafts, isEmpty);

      expect(bootstrapRepo.finishSetupInput?.organization.name, BootstrapDummyData.organizationName);
      expect(bootstrapRepo.finishSetupInput?.branch.name, BootstrapDummyData.branchName);
      expect(bootstrapRepo.finishSetupInput?.branch.code, BootstrapDummyData.branchCode);
      expect(bootstrapRepo.finishSetupInput?.staffAccounts, hasLength(1));
      expect(bootstrapRepo.finishSetupInput?.staffAccounts.first.username, 'admin');
    });

    test('resetInstallationForDevelopment clears wizard after successful RPC', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith((ref) => _FakeBootstrapRepository()),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(setupNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      final ok = await notifier.resetInstallationForDevelopment();

      expect(ok, isTrue);
      final state = container.read(setupNotifierProvider);
      expect(state.step, SetupWizardStep.organization);
      expect(state.organizationDraft, isNull);
      expect(state.isSubmitting, isFalse);
      expect(state.errorMessage, isNull);
    });

    test('resetInstallationForDevelopment surfaces RESET_SAFE_DELETE without connectivity fallback', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith(
            (ref) => _FakeBootstrapRepository(
              resetResult: RpcFailure(
                RpcResult.fromDynamic({
                  'success': false,
                  'error_code': 'RESET_SAFE_DELETE',
                  'error_message': 'Apply migration 20260521150000.',
                }),
              ),
            ),
          ),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container.read(setupNotifierProvider.notifier).resetInstallationForDevelopment();

      expect(ok, isFalse);
      expect(container.read(setupNotifierProvider).errorMessage, contains('20260521150000'));
    });
  });
}

class _RecordingBootstrapRepository extends BootstrapRepositoryImpl {
  _RecordingBootstrapRepository() : super(_ThrowingSupabaseClient());

  BootstrapFinishSetupInput? finishSetupInput;

  @override
  Future<BootstrapFinishSetupResult> finishSetup(BootstrapFinishSetupInput input) async {
    finishSetupInput = input;
    return const BootstrapFinishSetupResult(
      organizationId: 'org-dummy',
      branchId: 'branch-dummy',
      staffMemberIds: ['staff-dummy'],
    );
  }
}

class _FakeBootstrapRepository extends BootstrapRepositoryImpl {
  _FakeBootstrapRepository({this.resetResult}) : super(_ThrowingSupabaseClient());

  final Object? resetResult;

  @override
  Future<RpcResult> resetInstallationForDevelopment() async {
    final result = resetResult;
    if (result is RpcFailure) {
      throw result;
    }
    return const RpcResult(
      success: true,
      data: {'organizations_deleted': 1, 'branches_deleted': 1, 'had_organization_before_reset': true},
    );
  }
}

class _ThrowingSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
