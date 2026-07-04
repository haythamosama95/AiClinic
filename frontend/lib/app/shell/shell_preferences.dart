import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_clinic/core/logging/app_log.dart';
import 'package:ai_clinic/core/ui/navigation/nav_model.dart';

/// SharedPreferences keys — mirrors web `App.tsx` localStorage keys.
const shellSidebarCollapsedKey = 'aiclinic:sidebar-collapsed';
const shellBranchKey = 'aiclinic:branch';

@immutable
class ShellPreferencesState {
  const ShellPreferencesState({
    required this.sidebarCollapsed,
    required this.branchId,
  });

  final bool sidebarCollapsed;
  final String branchId;

  ShellPreferencesState copyWith({
    bool? sidebarCollapsed,
    String? branchId,
  }) {
    return ShellPreferencesState(
      sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
      branchId: branchId ?? this.branchId,
    );
  }
}

class ShellPreferencesNotifier extends Notifier<ShellPreferencesState> {
  @override
  ShellPreferencesState build() {
    unawaited(_loadPersisted());
    return ShellPreferencesState(
      sidebarCollapsed: false,
      branchId: mockBranches.first.id,
    );
  }

  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final collapsed = prefs.getString(shellSidebarCollapsedKey) == 'true';
      final storedBranch = prefs.getString(shellBranchKey);
      final branchId = storedBranch != null &&
              mockBranches.any((branch) => branch.id == storedBranch)
          ? storedBranch
          : mockBranches.first.id;

      state = state.copyWith(
        sidebarCollapsed: collapsed,
        branchId: branchId,
      );
    } on Exception catch (error) {
      AppLog.warning('shell_preferences.load_failed reason=${error.runtimeType}');
    }
  }

  Future<void> toggleSidebarCollapsed() async {
    final next = !state.sidebarCollapsed;
    state = state.copyWith(sidebarCollapsed: next);
    await _persistSidebarCollapsed(next);
  }

  Future<void> setBranchId(String branchId) async {
    if (!mockBranches.any((branch) => branch.id == branchId)) {
      return;
    }
    state = state.copyWith(branchId: branchId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(shellBranchKey, branchId);
    } on Exception catch (error) {
      AppLog.warning('shell_preferences.branch_save_failed reason=${error.runtimeType}');
    }
  }

  Future<void> _persistSidebarCollapsed(bool collapsed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(shellSidebarCollapsedKey, collapsed.toString());
    } on Exception catch (error) {
      AppLog.warning(
        'shell_preferences.sidebar_save_failed reason=${error.runtimeType}',
      );
    }
  }
}

final shellPreferencesProvider =
    NotifierProvider<ShellPreferencesNotifier, ShellPreferencesState>(
      ShellPreferencesNotifier.new,
    );
