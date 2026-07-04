import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/providers/command_bar_provider.dart';
import 'package:ai_clinic/core/ui/theme/theme.dart';

/// Authenticated application chrome: sidebar, top bar, scrollable main, and an
/// optional command-palette overlay slot.
///
/// Mirrors web `AppShell`.
class AppShell extends StatelessWidget {
  const AppShell({
    required this.sidebar,
    required this.topBar,
    required this.child,
    super.key,
    this.commandBar,
    this.fullWidth = false,
  });

  final Widget sidebar;
  final Widget topBar;
  final Widget child;
  final Widget? commandBar;
  final bool fullWidth;

  /// Content max width when [fullWidth] is false — matches web `max-w-6xl`.
  static const double contentMaxWidth = 1152;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final shell = ColoredBox(
      color: colors.surfaceCanvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sidebar,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                topBar,
                Expanded(
                  child: Material(
                    type: MaterialType.canvas,
                    color: colors.surfaceCanvas,
                    child: Semantics(
                      identifier: 'main',
                      label: 'Main content',
                      child: SingleChildScrollView(
                        key: const Key('main'),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: fullWidth
                                  ? double.infinity
                                  : contentMaxWidth,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.s6),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (commandBar == null) return shell;

    return CommandBarKeyboardScope(
      child: Stack(
        fit: StackFit.expand,
        children: [
          shell,
          commandBar!,
        ],
      ),
    );
  }
}

/// Convenience shell that accepts a pre-built command bar widget.
///
/// Wire [commandBar] to the navigation `CommandBar` once available (Agent 3).
class AppShellWithCommand extends StatelessWidget {
  const AppShellWithCommand({
    required this.sidebar,
    required this.topBar,
    required this.child,
    required this.commandBar,
    super.key,
    this.fullWidth = false,
  });

  final Widget sidebar;
  final Widget topBar;
  final Widget child;
  final Widget commandBar;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      sidebar: sidebar,
      topBar: topBar,
      commandBar: commandBar,
      fullWidth: fullWidth,
      child: child,
    );
  }
}
