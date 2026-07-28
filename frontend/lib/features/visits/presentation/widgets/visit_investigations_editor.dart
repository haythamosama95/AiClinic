import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_form_dialog.dart';

typedef InvestigationCreateHandler = void Function({required String name, String? note, String? investigationId});

typedef InvestigationUpdateHandler =
    void Function(String id, {required String name, String? note, String? investigationId});

typedef InvestigationArchiveHandler = void Function(String id);

/// Ordered investigations for the treatment step.
class VisitInvestigationsEditor extends StatelessWidget {
  const VisitInvestigationsEditor({
    required this.entries,
    required this.onCreate,
    required this.onUpdate,
    required this.onArchive,
    this.canEdit = true,
    super.key,
  });

  final List<VisitInvestigation> entries;
  final InvestigationCreateHandler onCreate;
  final InvestigationUpdateHandler onUpdate;
  final InvestigationArchiveHandler onArchive;
  final bool canEdit;

  Set<String> _usedInvestigationIds({VisitInvestigation? editing}) {
    return {
      for (final entry in entries)
        if (entry.investigationId != null && entry.id != editing?.id) entry.investigationId!,
    };
  }

  Future<void> _openDialog(BuildContext context, {VisitInvestigation? editing}) async {
    final result = await InvestigationFormDialog.show(
      context,
      usedInvestigationIds: _usedInvestigationIds(editing: editing),
      editingEntry: editing,
    );
    if (result == null) {
      return;
    }

    if (editing != null) {
      onUpdate(editing.id, name: result.name, note: result.note, investigationId: result.investigationId);
      return;
    }

    onCreate(name: result.name, note: result.note, investigationId: result.investigationId);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

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
            Text('Ordered investigations', style: AppTypography.title(context).copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.space1),
            Text(
              entries.isEmpty
                  ? 'Add labs, imaging, or other diagnostic tests.'
                  : '${entries.length} investigation${entries.length == 1 ? '' : 's'} to order',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space4),
            if (entries.isEmpty)
              _EmptyInvestigationsState(canEdit: canEdit, onAdd: () => _openDialog(context))
            else ...[
              Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.space3),
                    InvestigationEntryCard(
                      name: entries[i].name,
                      note: entries[i].note,
                      canEdit: canEdit,
                      onEdit: canEdit ? () => _openDialog(context, editing: entries[i]) : null,
                      onRemove: canEdit ? () => onArchive(entries[i].id) : null,
                    ),
                  ],
                ],
              ),
              if (canEdit) ...[
                const SizedBox(height: AppSpacing.space4),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.sm,
                    leadingIcon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: () => _openDialog(context),
                    child: const Text('Add another investigation'),
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

class _EmptyInvestigationsState extends StatelessWidget {
  const _EmptyInvestigationsState({required this.canEdit, required this.onAdd});

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
                child: Icon(Icons.science_outlined, size: 18, color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'No investigations added yet.',
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
                child: const Text('Add investigation'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
