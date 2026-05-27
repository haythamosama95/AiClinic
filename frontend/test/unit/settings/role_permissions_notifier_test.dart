import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/auth/presentation/providers/auth_notifier.dart';
import 'package:ai_clinic/features/settings/data/role_permissions_repository.dart';
import 'package:ai_clinic/features/settings/domain/permission_matrix_row.dart';
import 'package:ai_clinic/features/settings/presentation/providers/role_permissions_notifier.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/auth_test_support.dart';
import '../../support/settings_rpc_test_client.dart';
import '../../support/settings_table_test_client.dart';

void main() {
  group('RolePermissionsNotifier', () {
    test('setLocalGrant updates working matrix without persisting', () async {
      final container = _container(role: StaffRole.owner);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      final initial = await container.read(rolePermissionsProvider.future);
      expect(initial.isCellDirty(StaffRole.doctor, 'patients.view'), isFalse);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);

      final updated = container.read(rolePermissionsProvider).value!;
      expect(updated.hasUnsavedChanges, isTrue);
      expect(updated.isCellDirty(StaffRole.doctor, 'patients.view'), isTrue);
      expect(updated.matrix.isGranted(StaffRole.doctor, 'patients.view'), isFalse);
      expect(updated.savedMatrix.isGranted(StaffRole.doctor, 'patients.view'), isTrue);
    });

    test('reverting local grant clears dirty state without save', () async {
      final container = _container(role: StaffRole.owner);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: true);

      final ui = container.read(rolePermissionsProvider).value!;
      expect(ui.hasUnsavedChanges, isFalse);
      expect(ui.isCellDirty(StaffRole.doctor, 'patients.view'), isFalse);
    });

    test('saveChanges with no edits returns true without RPC', () async {
      final rpcClient = SettingsRpcTestClient();
      final container = _container(role: StaffRole.owner, rpcClient: rpcClient);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      final saved = await notifier.saveChanges();

      expect(saved, isTrue);
      expect(rpcClient.rpcCalls, isEmpty);
    });

    test('saveChanges persists only dirty cells', () async {
      final rpcClient = SettingsRpcTestClient();
      final container = _container(role: StaffRole.owner, rpcClient: rpcClient);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      final saved = await notifier.saveChanges();

      expect(saved, isTrue);
      expect(rpcClient.lastFunction, 'update_role_permission');
      expect(rpcClient.lastParams, containsPair('p_role', 'doctor'));
      expect(rpcClient.lastParams, containsPair('p_permission_key', 'patients.view'));
      expect(rpcClient.lastParams, containsPair('p_is_granted', false));

      final ui = container.read(rolePermissionsProvider).value!;
      expect(ui.hasUnsavedChanges, isFalse);
    });

    test('saveChanges issues one RPC per dirty cell', () async {
      final rpcClient = SettingsRpcTestClient();
      final container = _container(
        role: StaffRole.owner,
        rpcClient: rpcClient,
        matrixRows: [
          {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
          {'role': 'owner', 'permission_key': 'settings.manage_staff', 'is_granted': true, 'is_deleted': false},
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      notifier.setLocalGrant(role: StaffRole.owner, permissionKey: 'settings.manage_staff', isGranted: false);
      await notifier.saveChanges();

      final permissionUpdates = rpcClient.rpcCalls.where((c) => c.function == 'update_role_permission').toList();
      expect(permissionUpdates, hasLength(2));
    });

    test('local edits do not reload auth context', () async {
      _ReloadTrackingAuthNotifier.reloadCount = 0;
      final container = _container(role: StaffRole.owner, trackAuthReload: true);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);

      expect(_ReloadTrackingAuthNotifier.reloadCount, 0);
    });

    test('successful save reloads auth context once', () async {
      _ReloadTrackingAuthNotifier.reloadCount = 0;
      final container = _container(role: StaffRole.owner, trackAuthReload: true);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      await notifier.saveChanges();

      expect(_ReloadTrackingAuthNotifier.reloadCount, 1);
    });

    test('saveChanges RPC failure keeps unsaved working matrix', () async {
      final rpcClient = SettingsRpcTestClient(
        rpcResults: {
          'update_role_permission': {'success': false, 'error_code': 'FORBIDDEN', 'error_message': 'Denied'},
        },
      );
      final container = _container(role: StaffRole.owner, rpcClient: rpcClient);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      final saved = await notifier.saveChanges();

      expect(saved, isFalse);
      final ui = container.read(rolePermissionsProvider).value!;
      expect(ui.hasUnsavedChanges, isTrue);
      expect(ui.isSaving, isFalse);
      expect(ui.errorMessage, isNotNull);
    });

    test('setLocalGrant is ignored when permission matrix access is denied', () async {
      final container = _container(role: StaffRole.doctor);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      final initial = await container.read(rolePermissionsProvider.future);
      expect(initial.permissionDenied, isTrue);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);

      final after = container.read(rolePermissionsProvider).value!;
      expect(after.permissionDenied, isTrue);
      expect(after.hasUnsavedChanges, isFalse);
    });

    test('setLocalGrant ignores undefined matrix cells', () async {
      final container = _container(role: StaffRole.owner);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.labStaff, permissionKey: 'patients.view', isGranted: false);

      final ui = container.read(rolePermissionsProvider).value!;
      expect(ui.hasUnsavedChanges, isFalse);
    });

    test('discardChanges reverts working matrix', () async {
      final container = _container(role: StaffRole.owner);
      addTearDown(container.dispose);

      final notifier = container.read(rolePermissionsProvider.notifier);
      await container.read(rolePermissionsProvider.future);

      notifier.setLocalGrant(role: StaffRole.doctor, permissionKey: 'patients.view', isGranted: false);
      notifier.discardChanges();

      final ui = container.read(rolePermissionsProvider).value!;
      expect(ui.hasUnsavedChanges, isFalse);
      expect(ui.matrix.isGranted(StaffRole.doctor, 'patients.view'), isTrue);
    });

    test('administrator build is editable', () async {
      final container = _container(role: StaffRole.administrator);
      addTearDown(container.dispose);

      final ui = await container.read(rolePermissionsProvider.future);
      expect(ui.editable, isTrue);
      expect(ui.permissionDenied, isFalse);
    });
  });
}

ProviderContainer _container({
  required StaffRole role,
  SettingsRpcTestClient? rpcClient,
  List<Map<String, dynamic>>? matrixRows,
  bool trackAuthReload = false,
}) {
  final matrixClient = SettingsTableTestClient({
    'roles_permissions':
        matrixRows ??
        [
          {'role': 'doctor', 'permission_key': 'patients.view', 'is_granted': true, 'is_deleted': false},
        ],
  });

  return ProviderContainer(
    overrides: [
      authSessionProvider.overrideWith(
        () => _PresetAuthSessionNotifier(
          AuthSessionState(
            status: AuthSessionStatus.authenticated,
            context: sampleAuthSessionContext(role: role),
          ),
        ),
      ),
      rolePermissionsRepositoryProvider.overrideWithValue(
        _MatrixAndRpcRepository(fetchClient: matrixClient, rpcClient: rpcClient ?? SettingsRpcTestClient()),
      ),
      if (trackAuthReload) authNotifierProvider.overrideWith(_ReloadTrackingAuthNotifier.new),
    ],
  );
}

class _MatrixAndRpcRepository extends RolePermissionsRepositoryImpl {
  _MatrixAndRpcRepository({required SupabaseClient fetchClient, required SupabaseClient rpcClient})
    : _fetchClient = fetchClient,
      super(rpcClient);

  final SupabaseClient _fetchClient;

  @override
  Future<List<PermissionMatrixRow>> fetchMatrix() {
    return RolePermissionsRepositoryImpl(_fetchClient).fetchMatrix();
  }
}

class _PresetAuthSessionNotifier extends TestAuthSessionNotifier {
  _PresetAuthSessionNotifier(this.initial);

  final AuthSessionState initial;

  @override
  AuthSessionState build() => initial;
}

class _ReloadTrackingAuthNotifier extends AuthNotifier {
  static var reloadCount = 0;

  @override
  AuthUiState build() => const AuthUiState();

  @override
  Future<void> reloadContext() async {
    reloadCount++;
  }
}
