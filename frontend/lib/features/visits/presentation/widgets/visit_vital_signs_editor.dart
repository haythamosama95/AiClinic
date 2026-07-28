import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_form_dialog.dart';

typedef VitalSignCreateHandler =
    void Function({required String name, required String value, String? unit, String? predefinedVitalSignId});

typedef VitalSignUpdateHandler =
    void Function(
      String id, {
      required String name,
      required String value,
      String? unit,
      String? predefinedVitalSignId,
    });

typedef VitalSignArchiveHandler = void Function(String id);

/// Recorded vital signs for the findings step.
class VisitVitalSignsEditor extends StatelessWidget {
  const VisitVitalSignsEditor({
    required this.entries,
    required this.catalog,
    required this.onCreate,
    required this.onUpdate,
    required this.onArchive,
    this.canEdit = true,
    super.key,
  });

  final List<VisitVitalSign> entries;
  final List<CatalogItem> catalog;
  final VitalSignCreateHandler onCreate;
  final VitalSignUpdateHandler onUpdate;
  final VitalSignArchiveHandler onArchive;
  final bool canEdit;

  Set<String> _usedPredefinedIds({VisitVitalSign? editing}) {
    return {
      for (final entry in entries)
        if (entry.predefinedVitalSignId != null && entry.id != editing?.id) entry.predefinedVitalSignId!,
    };
  }

  bool _canAddMore() {
    if (catalog.isEmpty) {
      return false;
    }
    return _usedPredefinedIds().length < catalog.length;
  }

  Future<void> _openDialog(BuildContext context, {VisitVitalSign? editing}) async {
    final result = await VitalSignFormDialog.show(
      context,
      catalog: catalog,
      usedPredefinedIds: _usedPredefinedIds(editing: editing),
      editingEntry: editing,
    );
    if (result == null) {
      return;
    }

    if (editing != null) {
      onUpdate(
        editing.id,
        name: result.name,
        value: result.value,
        unit: result.unit,
        predefinedVitalSignId: result.predefinedVitalSignId,
      );
      return;
    }

    onCreate(
      name: result.name,
      value: result.value,
      unit: result.unit,
      predefinedVitalSignId: result.predefinedVitalSignId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canAddMore = _canAddMore();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Recorded measurements', style: AppTypography.title(context).copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.space1),
            Text(
              entries.isEmpty
                  ? 'Add each measurement as it is taken.'
                  : '${entries.length} vital sign${entries.length == 1 ? '' : 's'} documented',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space4),
            if (entries.isEmpty)
              _EmptyVitalSignsState(canEdit: canEdit && canAddMore, onAdd: () => _openDialog(context))
            else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  const columns = 4;
                  const spacing = AppSpacing.space3;
                  final cardWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final entry in entries)
                        SizedBox(
                          width: cardWidth,
                          child: VitalSignEntryCard(
                            label: entry.name,
                            value: entry.value,
                            unit: entry.unit,
                            canEdit: canEdit,
                            onEdit: canEdit ? () => _openDialog(context, editing: entry) : null,
                            onRemove: canEdit ? () => onArchive(entry.id) : null,
                          ),
                        ),
                    ],
                  );
                },
              ),
              if (canEdit && canAddMore) ...[
                const SizedBox(height: AppSpacing.space4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: () => _openDialog(context),
                    child: const Text('Add another vital sign'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyVitalSignsState extends StatelessWidget {
  const _EmptyVitalSignsState({required this.canEdit, required this.onAdd});

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space6),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.surfaceRaised, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space2 + 2),
                child: Icon(Icons.monitor_heart_outlined, size: 18, color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'No vital signs recorded yet.',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (canEdit) ...[
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: const Icon(Icons.add_rounded, size: 16),
                onPressed: onAdd,
                child: const Text('Add vital sign'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
