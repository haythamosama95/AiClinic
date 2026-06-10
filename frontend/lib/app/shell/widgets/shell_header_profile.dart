import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';

/// Account summary shown in the shell header: avatar, display name, and role.
///
/// Placeholder values until wired to the authenticated session.
class ShellHeaderProfile extends StatelessWidget {
  const ShellHeaderProfile({this.name = 'Alex Morgan', this.role = 'Clinic Administrator', super.key});

  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: CircleAvatar(
            radius: ShellTokens.headerAvatarSize / 2,
            backgroundColor: colors.muted,
            child: Text(
              _initials(name),
              style: theme.textTheme.labelMedium?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: SpacingTokens.sm),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: colors.foreground),
            ),
            Text(
              role,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
            ),
          ],
        ),
      ],
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'.toUpperCase();
  }
}
