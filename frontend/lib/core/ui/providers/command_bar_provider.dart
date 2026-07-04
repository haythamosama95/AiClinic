import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Command palette open/close state — mirrors web `CommandBarProvider`.
class CommandBarNotifier extends Notifier<bool> {
  FocusNode? _triggerFocusNode;

  @override
  bool build() => false;

  void openCommandBar() => state = true;

  void closeCommandBar() => state = false;

  void toggleCommandBar() => state = !state;

  void registerTrigger(FocusNode? node) => _triggerFocusNode = node;

  void focusTrigger() => _triggerFocusNode?.requestFocus();
}

final commandBarProvider = NotifierProvider<CommandBarNotifier, bool>(
  CommandBarNotifier.new,
);

class _ToggleCommandBarIntent extends Intent {
  const _ToggleCommandBarIntent();
}

/// Registers ⌘K / Ctrl+K to toggle the command palette.
///
/// Place above the authenticated shell (or inside [AppShell] when a command bar
/// slot is used).
class CommandBarKeyboardScope extends ConsumerWidget {
  const CommandBarKeyboardScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _ToggleCommandBarIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _ToggleCommandBarIntent(),
      },
      child: Actions(
        actions: {
          _ToggleCommandBarIntent: CallbackAction<_ToggleCommandBarIntent>(
            onInvoke: (_) {
              ref.read(commandBarProvider.notifier).toggleCommandBar();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
