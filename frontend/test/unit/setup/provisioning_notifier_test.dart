import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/setup/data/provisioning_repository.dart';
import 'package:ai_clinic/features/setup/presentation/providers/provisioning_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/fake_postgrest_rpc.dart';

void main() {
  group('ProvisioningNotifier', () {
    test('createStaffAccount calls RPC and stores result', () async {
      final rpcClient = RpcCaptureSupabaseClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(
                  role: StaffRole.administrator,
                  permissions: {'settings.manage_staff'},
                ),
              ),
            ),
          ),
          provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(provisioningNotifierProvider.notifier)
          .createStaffAccount(
            username: 'newrecep',
            fullName: 'New Receptionist',
            role: StaffRole.receptionist,
            branchIds: const ['00000000-0000-4000-8000-000000000201'],
            password: 'Secret12',
            phone: '201000000000',
          );

      expect(rpcClient.lastFunction, 'create_staff_account');
      expect(result, isNotNull);
      expect(result!.username, 'newrecep');
      expect(container.read(provisioningNotifierProvider).staffAccountsCreatedCount, 1);
    });

    test('createStaffAccount rejects empty branch list before RPC', () async {
      final rpcClient = RpcCaptureSupabaseClient();
      final container = ProviderContainer(
        overrides: [
          authSessionProvider.overrideWith(
            () => _PresetAuthSessionNotifier(
              AuthSessionState(
                status: AuthSessionStatus.authenticated,
                context: sampleAuthSessionContext(role: StaffRole.administrator),
              ),
            ),
          ),
          provisioningRepositoryProvider.overrideWithValue(ProvisioningRepositoryImpl(rpcClient)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(provisioningNotifierProvider.notifier)
          .createStaffAccount(
            username: 'newrecep',
            fullName: 'New Receptionist',
            role: StaffRole.receptionist,
            branchIds: const [],
            password: 'Secret12',
          );

      expect(result, isNull);
      expect(rpcClient.lastFunction, isNull);
      expect(container.read(provisioningNotifierProvider).errorMessage, 'Select at least one branch assignment.');
    });
  });
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}
