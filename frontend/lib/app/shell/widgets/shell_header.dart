import 'package:flutter/material.dart';

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
        child: Row(
          children: [
            if (pageTitle != null)
              Text(
                pageTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(color: colors.foreground),
              ),
            if (pageTitle != null) const SizedBox(width: SpacingTokens.lg),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: ShellTokens.headerSearchMaxWidth),
                  // TODO: Wire global search once the search API and routing are defined.
                  child: AppTextInput(
                    hintText: 'Search patients, appointments, visits…',
                    size: AppFieldSize.sm,
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
            ),
            const ShellHeaderProfile(),
            const SizedBox(width: ShellTokens.headerActionsGap),
            const ShellHeaderIconButton(icon: Icons.notifications_outlined, tooltip: 'Notifications'),
            const SizedBox(width: SpacingTokens.sm),
            const ShellHeaderIconButton(icon: Icons.settings_outlined, tooltip: 'Settings'),
          ],
        ),
      ),
    );
  }
}
