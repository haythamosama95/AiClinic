import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Design-system app shell primitive (web `AppShell`).
///
/// Distinct from production [AppShell] in `app/shell/layout/app_shell.dart`.
class AppAppShell extends StatelessWidget {
  const AppAppShell({
    required this.sidebar,
    required this.topBar,
    required this.child,
    this.commandBar,
    this.fullWidth = false,
    super.key,
  });

  final Widget sidebar;
  final Widget topBar;
  final Widget child;
  final Widget? commandBar;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ColoredBox(
      color: colors.surfaceCanvas,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sidebar,
          Expanded(
            child: Column(
              children: [
                topBar,
                Expanded(
                  child: SingleChildScrollView(
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: fullWidth ? double.infinity : AppShellTokens.contentMaxWidth,
                        ),
                        child: Padding(padding: const EdgeInsetsDirectional.all(AppSpacing.space6), child: child),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ?commandBar,
        ],
      ),
    );
  }
}
