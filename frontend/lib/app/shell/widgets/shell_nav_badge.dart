import 'package:flutter/material.dart';

import 'package:ai_clinic/app/shell/models/shell_nav_models.dart';
import 'package:ai_clinic/app/shell/shell_tokens.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';

/// Notification counter pill shown beside a nav item label.
class ShellNavBadge extends StatelessWidget {
  const ShellNavBadge({required this.count, required this.tone, super.key});

  final int count;
  final ShellNavBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final colors = context.semanticColors;
    final background = switch (tone) {
      ShellNavBadgeTone.warning => ShellTokens.badgeWarningBackground,
      ShellNavBadgeTone.success => ShellTokens.badgeSuccessBackground,
      ShellNavBadgeTone.neutral => colors.muted,
    };

    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
