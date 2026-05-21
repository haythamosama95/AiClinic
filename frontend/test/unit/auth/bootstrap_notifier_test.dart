import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/auth/data/bootstrap_repository.dart';
import 'package:ai_clinic/features/auth/domain/bootstrap_dummy_data.dart';
import 'package:ai_clinic/features/auth/presentation/providers/bootstrap_notifier.dart';
import 'package:ai_clinic/shared/providers/auth_session_provider.dart';
import 'package:ai_clinic/testing/auth_test_support.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('bootstrapMessageForRpc', () {
    test('maps known bootstrap error codes', () {
      expect(
        bootstrapMessageForRpc(
          RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'ORG_ALREADY_EXISTS'})),
        ),
        contains('already exists'),
      );

      expect(
        bootstrapMessageForRpc(
          RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'NOT_BOOTSTRAP_ADMIN'})),
        ),
        contains('bootstrap administrator'),
      );
    });

    test('falls back for unknown codes', () {
      expect(
        bootstrapMessageForRpc(RpcFailure(RpcResult.fromDynamic({'success': false, 'error_code': 'UNKNOWN'}))),
        contains('Unable to save'),
      );
    });

    test('maps RESET_SAFE_DELETE to migration hint', () {
      expect(
        bootstrapMessageForRpc(
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

  group('BootstrapNotifier', () {
    test('continueToBranchStep stores draft without organizationId', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(bootstrapNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Sunrise Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      expect(ok, isTrue);
      final state = container.read(bootstrapNotifierProvider);
      expect(state.step, BootstrapWizardStep.branch);
      expect(state.organizationId, isNull);
      expect(state.organizationDraft?.name, 'Sunrise Clinic');
    });

    test('continueToBranchStep rejects invalid currency', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(bootstrapNotifierProvider.notifier);

      final ok = notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'NOTREAL', timezone: 'Africa/Cairo');

      expect(ok, isFalse);
      expect(container.read(bootstrapNotifierProvider).step, BootstrapWizardStep.organization);
    });

    test('finishSetupWithDummyData stores draft and calls repository', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith((ref) => _RecordingBootstrapRepository()),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final ok = await container.read(bootstrapNotifierProvider.notifier).finishSetupWithDummyData();

      expect(ok, isTrue);
      final state = container.read(bootstrapNotifierProvider);
      expect(state.step, BootstrapWizardStep.complete);
      expect(state.organizationId, 'org-dummy');
      expect(state.branchId, 'branch-dummy');

      final repo = container.read(bootstrapRepositoryProvider) as _RecordingBootstrapRepository;
      expect(repo.organizationInput?.name, BootstrapDummyData.organizationName);
      expect(repo.branchInput?.name, BootstrapDummyData.branchName);
      expect(repo.branchInput?.code, BootstrapDummyData.branchCode);
    });

    test('resetInstallationForDevelopment clears wizard after successful RPC', () async {
      final container = ProviderContainer(
        overrides: [
          bootstrapRepositoryProvider.overrideWith((ref) => _FakeBootstrapRepository()),
          authSessionProvider.overrideWith(TestAuthSessionNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(bootstrapNotifierProvider.notifier);
      notifier.continueToBranchStep(name: 'Clinic', currencyCode: 'EGP', timezone: 'Africa/Cairo');

      final ok = await notifier.resetInstallationForDevelopment();

      expect(ok, isTrue);
      final state = container.read(bootstrapNotifierProvider);
      expect(state.step, BootstrapWizardStep.organization);
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

      final ok = await container.read(bootstrapNotifierProvider.notifier).resetInstallationForDevelopment();

      expect(ok, isFalse);
      expect(container.read(bootstrapNotifierProvider).errorMessage, contains('20260521150000'));
    });
  });
}

class _RecordingBootstrapRepository extends BootstrapRepository {
  _RecordingBootstrapRepository() : super(_ThrowingSupabaseClient());

  BootstrapOrganizationInput? organizationInput;
  BootstrapBranchInput? branchInput;

  @override
  Future<String> createOrganization(BootstrapOrganizationInput input) async {
    organizationInput = input;
    return 'org-dummy';
  }

  @override
  Future<String> createBranch(BootstrapBranchInput input) async {
    branchInput = input;
    return 'branch-dummy';
  }
}

class _FakeBootstrapRepository extends BootstrapRepository {
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
