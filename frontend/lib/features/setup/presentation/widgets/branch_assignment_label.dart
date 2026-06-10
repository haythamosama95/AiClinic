import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/theme.dart';
import 'package:ai_clinic/features/setup/domain/branch_summary.dart';

/// Branch name with optional info icon showing full branch details on hover.
class BranchAssignmentLabel extends StatelessWidget {
  const BranchAssignmentLabel({super.key, required this.branch, this.fallbackLabel});

  final BranchSummary? branch;
  final String? fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final label = branch?.name ?? fallbackLabel ?? 'Branch';
    final tooltip = branch?.detailTooltip;

    return Row(
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (tooltip != null) ...[
          const SizedBox(width: SpacingTokens.xs),
          Tooltip(
            message: tooltip,
            preferBelow: false,
            child: Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ],
    );
  }
}
