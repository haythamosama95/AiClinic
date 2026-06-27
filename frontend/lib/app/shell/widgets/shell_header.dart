import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_icon_button.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Top chrome for the authenticated shell: page title and account actions.
class ShellHeader extends StatelessWidget {
  const ShellHeader({this.pageTitle, super.key});

  final String? pageTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return SizedBox(
      height: ShellTokens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ShellTokens.contentPanelInset),
        child: Row(
          children: [
            if (pageTitle != null)
              Expanded(
                child: Text(
                  pageTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(color: colors.foreground),
                ),
              )
            else
              const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ShellHeaderProfile(),
                const SizedBox(width: ShellTokens.headerActionsGap),
                const ShellHeaderIconButton(icon: Icons.notifications_outlined, tooltip: 'Notifications'),
                const SizedBox(width: SpacingTokens.sm),
                ShellHeaderIconButton(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
                  onTap: () => context.go(AppRoutes.settings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
