import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Intent dispatched by the global command-bar keyboard shortcut.
class ToggleCommandBarIntent extends Intent {
  const ToggleCommandBarIntent();
}

/// Open/close state and trigger focus registration for the command bar (B23 UI).
class CommandBarNotifier extends Notifier<bool> {
  FocusNode? _triggerFocusNode;

  @override
  bool build() => false;

  /// Whether the command bar overlay is open.
  bool get isOpen => state;

  void openCommandBar() => state = true;

  void closeCommandBar() => state = false;

  void toggleCommandBar() => state = !state;

  /// Registers the shell trigger's [FocusNode] for focus return on dismiss.
  void registerTrigger(FocusNode? node) {
    _triggerFocusNode = node;
  }

  /// Returns focus to the registered trigger, if any.
  void focusTrigger() {
    _triggerFocusNode?.requestFocus();
  }
}

/// Command bar open state (`true` = open).
final commandBarProvider = NotifierProvider<CommandBarNotifier, bool>(CommandBarNotifier.new);

/// Platform-aware ⌘K / Ctrl+K shortcut wiring for [commandBarProvider].
///
/// Wrap the app shell (or [MaterialApp.builder]) so the shortcut is active
/// tree-wide. Does not render command bar UI — only toggles provider state.
class CommandBarShortcuts extends ConsumerWidget {
  const CommandBarShortcuts({required this.child, super.key});

  final Widget child;

  static final Map<ShortcutActivator, Intent> _shortcuts = {
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true): const ToggleCommandBarIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true): const ToggleCommandBarIntent(),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: {
          ToggleCommandBarIntent: CallbackAction<ToggleCommandBarIntent>(
            onInvoke: (_) {
              ref.read(commandBarProvider.notifier).toggleCommandBar();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}
