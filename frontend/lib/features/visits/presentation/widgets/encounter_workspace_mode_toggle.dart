import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Guided vs expert workspace mode switch (014 US5 / FR-019).
class EncounterWorkspaceModeToggle extends ConsumerWidget {
  const EncounterWorkspaceModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.visitTheme;
    final mode = ref.watch(workspaceModeProvider);
    final isGuided = mode == WorkspaceMode.guided;
    final modeNotifier = ref.read(workspaceModeProvider.notifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.tile,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        border: Border.all(color: theme.hairlineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeChip(
            key: const Key('encounter_mode_guided'),
            label: 'Guided',
            icon: Icons.view_sidebar_outlined,
            selected: isGuided,
            onTap: isGuided ? null : modeNotifier.toggleMode,
          ),
          _ModeChip(
            key: const Key('encounter_mode_expert'),
            label: 'Expert',
            icon: Icons.view_agenda_outlined,
            selected: !isGuided,
            onTap: !isGuided ? null : modeNotifier.toggleMode,
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.icon, required this.selected, this.onTap, super.key});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Material(
      color: selected ? theme.pulse.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(theme.tileRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.tileRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? theme.pulseDeep : theme.mutedInk),
              const SizedBox(width: SpacingTokens.xs),
              Text(label, style: theme.bodyStrong(size: 13, color: selected ? theme.pulseDeep : theme.mutedInk)),
            ],
          ),
        ),
      ),
    );
  }
}
