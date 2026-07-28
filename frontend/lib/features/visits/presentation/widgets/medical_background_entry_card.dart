import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Accent tone for medical-background entry cards.
enum MedicalBackgroundAccent { warning, danger, info }

/// Compact card for a single chronic condition, allergy, or medication entry.
class MedicalBackgroundEntryCard extends StatelessWidget {
  const MedicalBackgroundEntryCard({
    required this.title,
    this.note,
    required this.accent,
    this.onEdit,
    this.onRemove,
    this.canEdit = true,
    super.key,
  });

  final String title;
  final String? note;
  final MedicalBackgroundAccent accent;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accentColor = _accentColor(colors, accent);
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
              child: ColoredBox(color: accentColor.withValues(alpha: 0.55), child: const SizedBox(width: 3)),
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
                      title,
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
                    const SizedBox(width: AppSpacing.space1),
                    AppIconButton(
                      icon: Icon(Icons.edit_outlined, size: 16, color: colors.iconMuted),
                      label: 'Edit $title',
                      size: AppIconButtonSize.sm,
                      tooltipDisabled: true,
                      onPressed: onEdit,
                    ),
                    AppIconButton(
                      icon: Icon(Icons.close_rounded, size: 16, color: colors.iconMuted),
                      label: 'Remove $title',
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

  static Color _accentColor(AppSemanticColors colors, MedicalBackgroundAccent accent) {
    return switch (accent) {
      MedicalBackgroundAccent.warning => colors.statusWarningFg,
      MedicalBackgroundAccent.danger => colors.statusDangerFg,
      MedicalBackgroundAccent.info => colors.statusInfoFg,
    };
  }
}
