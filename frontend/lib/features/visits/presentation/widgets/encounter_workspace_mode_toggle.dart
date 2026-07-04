import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/presentation/providers/workspace_mode_provider.dart';

/// Guided stepper vs expert single-page toggle (014 US5).
class EncounterWorkspaceModeToggle extends ConsumerWidget {
  const EncounterWorkspaceModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(workspaceModeProvider);

    return AppSegmentedControl<WorkspaceMode>(
      options: const [
        AppSegmentedOption(
          value: WorkspaceMode.guided,
          label: 'Guided',
          icon: LucideIcons.listOrdered,
        ),
        AppSegmentedOption(
          value: WorkspaceMode.expert,
          label: 'Expert',
          icon: LucideIcons.layoutList,
        ),
      ],
      value: mode,
      onChanged: (next) => ref.read(workspaceModeProvider.notifier).setMode(next),
      semanticLabel: 'Workspace mode',
      size: AppSegmentedControlSize.sm,
    );
  }
}
