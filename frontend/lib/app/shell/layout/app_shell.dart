import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/layout/shell_page_transition.dart';
import 'package:ai_clinic/app/shell/navigation/shell_nav_config.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';

/// Persistent authenticated frame (`05-patterns` §1, web `AppShell`).
class AppShell extends StatelessWidget {
  const AppShell({
    required this.sidebar,
    required this.topBar,
    required this.child,
    required this.pageKey,
    this.fullWidth = false,
    this.fillViewport = false,
    super.key,
  });

  final Widget sidebar;
  final Widget topBar;
  final Widget child;
  final Object pageKey;
  final bool fullWidth;

  /// When true, the content region fills the viewport and does not scroll at the shell level.
  final bool fillViewport;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox.expand(
      child: ColoredBox(
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
                    child: ColoredBox(
                      color: colors.surfaceCanvas,
                      child: ShellPageTransition(
                        pageKey: pageKey,
                        child: child,
                        builder: (context, pageContent, activePageKey) {
                          final framed = _buildFrame(pageContent);
                          final effectiveFillViewport =
                              fillViewport || ShellNavConfig.isDesignSystemLocation(activePageKey.toString());
                          if (effectiveFillViewport) {
                            return framed;
                          }
                          return SingleChildScrollView(primary: true, child: framed);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrame(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: fullWidth ? double.infinity : AppShellTokens.contentMaxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}
