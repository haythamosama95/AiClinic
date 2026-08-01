import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Compact card for a single ordered investigation.
class InvestigationEntryCard extends StatelessWidget {
  const InvestigationEntryCard({
    required this.name,
    this.note,
    this.onEdit,
    this.onRemove,
    this.canEdit = true,
    super.key,
  });

  final String name;
  final String? note;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceDefault,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: ColoredBox(color: colors.actionPrimary.withValues(alpha: 0.5), child: const SizedBox(width: 3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space4,
                AppSpacing.space2 + 2,
                AppSpacing.space2,
                AppSpacing.space2 + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      name,
                      style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space3),
                  Container(width: 1, height: 28, color: colors.borderSubtle),
                  const SizedBox(width: AppSpacing.space3),
                  Expanded(
                    flex: 7,
                    child: Text(
                      hasNote ? trimmedNote : '—',
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: hasNote ? colors.textSecondary : colors.textTertiary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (canEdit) ...[
                    AppIconButton(
                      icon: Icon(Icons.edit_outlined, size: 15, color: colors.iconMuted),
                      label: 'Edit $name',
                      size: AppIconButtonSize.sm,
                      tooltipDisabled: true,
                      onPressed: onEdit,
                    ),
                    AppIconButton(
                      icon: Icon(Icons.delete_outline, size: 15, color: colors.iconMuted),
                      label: 'Remove $name',
                      size: AppIconButtonSize.sm,
                      tooltipDisabled: true,
                      onPressed: onRemove,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
