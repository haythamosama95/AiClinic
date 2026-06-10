import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Content-area page title aligned with the top of the sidebar.
class ShellHeader extends StatelessWidget {
  const ShellHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: ShellTokens.headerHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(right: SpacingTokens.lg),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
