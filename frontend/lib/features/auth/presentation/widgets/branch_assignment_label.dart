import 'package:flutter/material.dart';

import 'package:ai_clinic/app/theme/app_colors.dart';
import 'package:ai_clinic/features/auth/domain/branch_summary.dart';

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
          const SizedBox(width: AppSpacing.xs),
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
