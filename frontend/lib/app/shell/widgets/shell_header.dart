import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_icon_button.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_text_field.dart';

/// Top chrome for the authenticated shell: global search and account actions.
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final searchWidth = math.min(ShellTokens.headerSearchMaxWidth, constraints.maxWidth).toDouble();
            final titleMaxWidth = math.max(0.0, (constraints.maxWidth - searchWidth) / 2 - SpacingTokens.sm);

            return Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: searchWidth),
                    // TODO: Wire global search once the search API and routing are defined.
                    child: AppTextInput(
                      hintText: 'Search patients, appointments, visits…',
                      size: AppFieldSize.sm,
                      prefixIcon: const Icon(Icons.search, size: 18),
                    ),
                  ),
                ),
                if (pageTitle != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: titleMaxWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        pageTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(color: colors.foreground),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Row(
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
