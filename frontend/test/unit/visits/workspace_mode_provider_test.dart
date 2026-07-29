import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/auth/domain/auth_session.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/auth_test_support.dart';

const _staffIdA = '00000000-0000-4000-8000-000000000010';
const _staffIdB = '00000000-0000-4000-8000-000000000011';
const _workspaceModeKeyPrefix = 'visit_workspace_mode';

String _storageKeyFor(String? staffId) {
  if (staffId == null || staffId.isEmpty) {
    return _workspaceModeKeyPrefix;
  }
  return '${_workspaceModeKeyPrefix}_$staffId';
}

AuthSessionState _authForStaff(String staffId) {
  return AuthSessionState(
    status: AuthSessionStatus.authenticated,
    context: sampleAuthSessionContext().copyWith(
      staffProfile: StaffProfile(
        staffMemberId: staffId,
        fullName: 'Test Staff',
        role: StaffRole.administrator,
        isBootstrapAdmin: false,
        isActive: true,
      ),
    ),
  );
}

Future<void> _pumpPersistedLoad(ProviderContainer container) async {
  container.read(workspaceModeProvider);
  await pumpEventQueue();
  await pumpEventQueue();
}

ProviderContainer _createContainer({
  required MutableAuthSessionNotifier auth,
}) {
  final container = ProviderContainer(
    overrides: [authSessionProvider.overrideWith(() => auth)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkspaceMode wire encoding', () {
    test('trivial: wireValue round-trips guided and expert', () {
      expect(WorkspaceMode.guided.wireValue, 'guided');
      expect(WorkspaceMode.expert.wireValue, 'expert');
      expect(WorkspaceMode.fromWire('guided'), WorkspaceMode.guided);
      expect(WorkspaceMode.fromWire('expert'), WorkspaceMode.expert);
    });

    test('edge case: unknown, empty, null, and mis-cased wire values default to guided', () {
      expect(WorkspaceMode.fromWire(null), WorkspaceMode.guided);
      expect(WorkspaceMode.fromWire(''), WorkspaceMode.guided);
      expect(WorkspaceMode.fromWire('GUIDED'), WorkspaceMode.guided);
      expect(WorkspaceMode.fromWire('Expert'), WorkspaceMode.guided);
      expect(WorkspaceMode.fromWire('accordion'), WorkspaceMode.guided);
    });
  });

  group('workspaceModeProvider', () {
    test('trivial: defaults to guided when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = MutableAuthSessionNotifier(_authForStaff(_staffIdA));
      final container = _createContainer(auth: auth);

      await _pumpPersistedLoad(container);

      expect(container.read(workspaceModeProvider), WorkspaceMode.guided);
    });

    test('advanced: setMode persists and updates in-memory state', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = MutableAuthSessionNotifier(_authForStaff(_staffIdA));
      final container = _createContainer(auth: auth);
      await _pumpPersistedLoad(container);

      await container.read(workspaceModeProvider.notifier).setMode(WorkspaceMode.expert);

      expect(container.read(workspaceModeProvider), WorkspaceMode.expert);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_storageKeyFor(_staffIdA)), 'expert');
    });

    test('advanced: toggleMode flips guided to expert and back', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = MutableAuthSessionNotifier(_authForStaff(_staffIdA));
      final container = _createContainer(auth: auth);
      await _pumpPersistedLoad(container);

      await container.read(workspaceModeProvider.notifier).toggleMode();
      expect(container.read(workspaceModeProvider), WorkspaceMode.expert);

      await container.read(workspaceModeProvider.notifier).toggleMode();
      expect(container.read(workspaceModeProvider), WorkspaceMode.guided);
    });

    test('advanced: restores mode from pre-seeded SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        _storageKeyFor(_staffIdA): 'expert',
      });
      final auth = MutableAuthSessionNotifier(_authForStaff(_staffIdA));
      final container = _createContainer(auth: auth);

      await _pumpPersistedLoad(container);

      expect(container.read(workspaceModeProvider), WorkspaceMode.expert);
    });

    test('edge case: corrupt persisted value falls back to guided', () async {
      SharedPreferences.setMockInitialValues({
        _storageKeyFor(_staffIdA): 'not-a-mode',
      });
      final auth = MutableAuthSessionNotifier(_authForStaff(_staffIdA));
      final container = _createContainer(auth: auth);

      await _pumpPersistedLoad(container);

      expect(container.read(workspaceModeProvider), WorkspaceMode.guided);
    });

    test('edge case: per-staff storage keys do not collide', () async {
      SharedPreferences.setMockInitialValues({
        _storageKeyFor(_staffIdA): 'expert',
        _storageKeyFor(_staffIdB): 'guided',
      });
      final auth = MutableAuthSessionNotifier(_authForStaff(_staffIdA));
      final container = _createContainer(auth: auth);
      await _pumpPersistedLoad(container);
      expect(container.read(workspaceModeProvider), WorkspaceMode.expert);

      auth.replace(_authForStaff(_staffIdB));
      await _pumpPersistedLoad(container);

      expect(container.read(workspaceModeProvider), WorkspaceMode.guided);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_storageKeyFor(_staffIdA)), 'expert');
      expect(prefs.getString(_storageKeyFor(_staffIdB)), 'guided');
    });

    test('invalid state: staff without id uses shared fallback key', () async {
      SharedPreferences.setMockInitialValues({
        _storageKeyFor(null): 'expert',
      });
      final auth = MutableAuthSessionNotifier(
        AuthSessionState(status: AuthSessionStatus.authenticated, context: null),
      );
      final container = _createContainer(auth: auth);

      await _pumpPersistedLoad(container);

      expect(container.read(workspaceModeProvider), WorkspaceMode.expert);
    });
  });
}
