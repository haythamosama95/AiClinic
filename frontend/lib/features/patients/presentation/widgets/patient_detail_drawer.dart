import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_sheets.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';

const _drawerWidth = 480.0;

/// Right-side detail panel for a selected patient (content TBD).
class PatientDetailDrawer extends StatelessWidget {
  const PatientDetailDrawer({required this.row, super.key});

  final PatientTableRow row;

  static Future<void> show(BuildContext context, PatientTableRow row) {
    return AppSheets.showModal<void>(
      context: context,
      side: AppSheetSide.right,
      width: _drawerWidth,
      builder: (context) => PatientDetailDrawer(row: row),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.item.fullName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AppIconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              'Patient ID ${row.displayId}',
              style: theme.textTheme.labelSmall?.copyWith(color: colors.mutedForeground),
            ),
            const SizedBox(height: SpacingTokens.lg),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Center(
                  child: Text(
                    'Patient detail view — coming soon',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
