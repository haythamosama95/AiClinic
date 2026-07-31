import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sidebarCollapsedKey = 'aiclinic:sidebar-collapsed';

/// Persists sidebar collapsed state across sessions.
class ShellSidebarCollapsedNotifier extends Notifier<bool> {
  @override
  bool build() {
    Future<void>.microtask(_load);
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final collapsed = prefs.getBool(_sidebarCollapsedKey) ?? false;
    if (state != collapsed) {
      state = collapsed;
    }
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sidebarCollapsedKey, state);
  }
}

final shellSidebarCollapsedProvider = NotifierProvider<ShellSidebarCollapsedNotifier, bool>(
  ShellSidebarCollapsedNotifier.new,
);
