import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_icon_button.dart';
import 'package:ai_clinic/app/shell/widgets/shell_header_profile.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/input/app_text_field.dart';

/// Top chrome for the authenticated shell: global search and account actions.
class ShellHeader extends StatelessWidget {
  const ShellHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ShellTokens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ShellTokens.contentPanelInset),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: ShellTokens.headerSearchMaxWidth),
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
