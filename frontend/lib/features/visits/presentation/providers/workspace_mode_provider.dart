import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/logging/app_log.dart';

/// Guided stepper vs expert single-page accordion (014 US5 / FR-019).
enum WorkspaceMode {
  guided,
  expert;

  String get wireValue => name;

  static WorkspaceMode fromWire(String? value) => switch (value) {
    'expert' => WorkspaceMode.expert,
    _ => WorkspaceMode.guided,
  };
}

const _workspaceModeKeyPrefix = 'visit_workspace_mode';

String _storageKey(AuthSessionState auth) {
  final staffId = auth.context?.staffProfile.staffMemberId;
  if (staffId == null || staffId.isEmpty) {
    return _workspaceModeKeyPrefix;
  }
  return '${_workspaceModeKeyPrefix}_$staffId';
}

/// Workspace mode with best-effort local persistence per staff member.
final workspaceModeProvider = NotifierProvider<WorkspaceModeNotifier, WorkspaceMode>(WorkspaceModeNotifier.new);

class WorkspaceModeNotifier extends Notifier<WorkspaceMode> {
  @override
  WorkspaceMode build() {
    _loadPersistedMode();
    return WorkspaceMode.guided;
  }

  Future<void> _loadPersistedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(ref.read(authSessionProvider));
      final stored = prefs.getString(key);
      if (stored == null) {
        return;
      }
      state = WorkspaceMode.fromWire(stored);
    } on Exception catch (error) {
      AppLog.warning('visits.workspace_mode.load_failed reason=${error.runtimeType}');
    }
  }

  Future<void> setMode(WorkspaceMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey(ref.read(authSessionProvider));
      await prefs.setString(key, mode.wireValue);
    } on Exception catch (error) {
      AppLog.warning('visits.workspace_mode.save_failed reason=${error.runtimeType}');
    }
  }

  Future<void> toggleMode() => setMode(state == WorkspaceMode.guided ? WorkspaceMode.expert : WorkspaceMode.guided);
}
