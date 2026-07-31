import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_entry_list.dart';

/// Investigations editor block (web `InvestigationsEditor`).
class InvestigationsEditor extends ConsumerStatefulWidget {
  const InvestigationsEditor({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<InvestigationsEditor> createState() => _InvestigationsEditorState();
}

class _InvestigationsEditorState extends ConsumerState<InvestigationsEditor> {
  var _dialogOpen = false;
  String? _editingId;

  void _openAddDialog() {
    setState(() {
      _editingId = null;
      _dialogOpen = true;
    });
  }

  void _openEditDialog(String id) {
    setState(() {
      _editingId = id;
      _dialogOpen = true;
    });
  }

  void _handleDialogOpenChange(bool open) {
    setState(() {
      _dialogOpen = open;
      if (!open) {
        _editingId = null;
      }
    });
  }

  Set<String> _usedInvestigationIds(List<VisitInvestigation> investigations, {String? excludeLineId}) {
    return {
      for (final investigation in investigations)
        if (investigation.id != excludeLineId && investigation.investigationId != null)
          investigation.investigationId!,
    };
  }

  String? _orderedVisitDateLabel(VisitInvestigation investigation) {
    final date = investigation.orderedVisitDate;
    if (date == null) {
      return null;
    }
    return DateFormat.yMMMd().format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(visitDocumentationProvider(widget.visitId));
    final state = doc.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final colors = context.appColors;
    final canEdit = state.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final investigations = state.effectiveVisit.investigations;
    final priorPending = state.effectiveVisit.pendingInvestigations;
    final hasEntries = investigations.isNotEmpty || priorPending.isNotEmpty;
    const canAddMore = true;
    final editingEntry = _editingId == null
        ? null
        : investigations.where((investigation) => investigation.id == _editingId).firstOrNull;
    final usedIdsForDialog = _usedInvestigationIds(investigations, excludeLineId: _editingId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceDefault,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ordered investigations',
                  style: AppTypography.title(context).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space05),
                Text(
                  investigations.isNotEmpty
                      ? '${investigations.length} investigation${investigations.length == 1 ? '' : 's'} to order'
                      : 'Add labs, imaging, or other diagnostic tests.',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space4),
                if (!hasEntries)
                  _EmptyInvestigationsState(
                    canAddMore: canAddMore && canEdit,
                    onAdd: _openAddDialog,
                  )
                else ...[
                  if (priorPending.isNotEmpty)
                    VisitEntryList<VisitInvestigation>(
                      items: priorPending,
                      itemId: (investigation) => investigation.id,
                      wrap: true,
                      maxCrossAxisCount: 4,
                      itemBuilder: (context, investigation) => InvestigationEntryCard(
                        investigation: investigation,
                        typeMeta: _orderedVisitDateLabel(investigation),
                      ),
                    ),
                  if (priorPending.isNotEmpty && investigations.isNotEmpty) const SizedBox(height: AppSpacing.space3),
                  if (investigations.isNotEmpty)
                    VisitEntryList<VisitInvestigation>(
                      items: investigations,
                      itemId: (investigation) => investigation.id,
                      wrap: true,
                      maxCrossAxisCount: 4,
                      itemBuilder: (context, investigation) => InvestigationEntryCard(
                        investigation: investigation,
                        onEdit: canEdit ? () => _openEditDialog(investigation.id) : null,
                        onRemove: canEdit ? () => notifier.stageArchiveInvestigation(investigation.id) : null,
                      ),
                    ),
                ],
                if (hasEntries && canAddMore && canEdit) ...[
                  const SizedBox(height: AppSpacing.space4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.add, size: 14),
                      onPressed: _openAddDialog,
                      child: const Text('Add another investigation'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        InvestigationFormDialog(
          open: _dialogOpen,
          onOpenChange: _handleDialogOpenChange,
          visitId: widget.visitId,
          usedInvestigationIds: usedIdsForDialog,
          editingEntry: editingEntry,
          onSubmit: ({
            required name,
            note,
            investigationId,
            updateInvestigationId = false,
          }) {
            if (_editingId != null) {
              notifier.stageUpdateInvestigation(
                investigationLineId: _editingId!,
                name: name,
                note: note,
                investigationId: investigationId,
                updateInvestigationId: updateInvestigationId,
              );
            } else {
              notifier.stageCreateInvestigation(
                name: name,
                note: note,
                investigationId: investigationId,
              );
            }
          },
        ),
      ],
    );
  }
}

class _EmptyInvestigationsState extends StatelessWidget {
  const _EmptyInvestigationsState({required this.canAddMore, required this.onAdd});

  final bool canAddMore;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space8),
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space3),
                  child: Icon(Icons.science_outlined, size: 18, color: colors.textTertiary),
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'No investigations added yet.',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: const Icon(Icons.add, size: 14),
                onPressed: canAddMore ? onAdd : null,
                disabled: !canAddMore,
                child: const Text('Add investigation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
