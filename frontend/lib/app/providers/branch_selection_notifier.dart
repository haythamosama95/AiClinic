import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';

/// Manages active branch selection as a separate concern from auth lifecycle.
///
/// Reads the current session context to validate branch membership before
/// accepting a selection. The selected branch is reflected back into
/// [AuthSessionState.context.activeBranchId] via the [AuthSessionNotifier].
class BranchSelectionNotifier extends Notifier<String?> {
  @override
  String? build() {
    final context = ref.watch(authSessionProvider).context;
    return context?.activeBranchId;
  }

  /// Selects a branch if the authenticated user is assigned to it.
  void selectBranch(String branchId) {
    final context = ref.read(authSessionProvider).context;
    if (context == null || !context.branchIds.contains(branchId)) {
      return;
    }
    ref.read(authSessionProvider.notifier).setActiveBranch(branchId);
  }

  void clearBranch() {
    state = null;
  }
}

final branchSelectionProvider = NotifierProvider<BranchSelectionNotifier, String?>(BranchSelectionNotifier.new);
