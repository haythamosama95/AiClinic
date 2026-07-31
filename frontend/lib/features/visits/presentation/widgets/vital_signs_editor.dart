import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_entry_list.dart';

/// Vital signs editor block (web `VitalSignsEditor`).
class VitalSignsEditor extends ConsumerStatefulWidget {
  const VitalSignsEditor({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<VitalSignsEditor> createState() => _VitalSignsEditorState();
}

class _VitalSignsEditorState extends ConsumerState<VitalSignsEditor> {
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

  Set<String> _usedPredefinedIds(List<VisitVitalSign> signs, {String? excludeId}) {
    return {
      for (final sign in signs)
        if (sign.id != excludeId && sign.predefinedVitalSignId != null) sign.predefinedVitalSignId!,
    };
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
    final signs = state.effectiveVisit.vitalSigns;
    final catalog = state.predefinedVitalSigns;
    final usedPredefinedIds = _usedPredefinedIds(signs);
    final canAddMore = usedPredefinedIds.length < catalog.length;
    final editingEntry = _editingId == null ? null : signs.where((sign) => sign.id == _editingId).firstOrNull;
    final usedIdsForDialog = _usedPredefinedIds(signs, excludeId: _editingId);

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
                  'Recorded measurements',
                  style: AppTypography.title(context).copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.space05),
                Text(
                  signs.isNotEmpty
                      ? '${signs.length} vital sign${signs.length == 1 ? '' : 's'} documented'
                      : 'Add each measurement as it is taken.',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space4),
                if (signs.isEmpty)
                  _EmptyVitalSignsState(
                    canAddMore: canAddMore && canEdit,
                    onAdd: _openAddDialog,
                  )
                else
                  VisitEntryList<VisitVitalSign>(
                    items: signs,
                    itemId: (sign) => sign.id,
                    wrap: true,
                    maxCrossAxisCount: 4,
                    itemBuilder: (context, sign) => VitalSignEntryCard(
                      sign: sign,
                      catalog: catalog,
                      onEdit: canEdit ? () => _openEditDialog(sign.id) : null,
                      onRemove: canEdit ? () => notifier.stageArchiveVitalSign(sign.id) : null,
                    ),
                  ),
                if (signs.isNotEmpty && canAddMore && canEdit) ...[
                  const SizedBox(height: AppSpacing.space4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.add, size: 14),
                      onPressed: _openAddDialog,
                      child: const Text('Add another vital sign'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        VitalSignFormDialog(
          open: _dialogOpen,
          onOpenChange: _handleDialogOpenChange,
          predefinedVitalSigns: catalog,
          usedPredefinedIds: usedIdsForDialog,
          editingEntry: editingEntry,
          onSubmit: ({required name, required value, unit, predefinedVitalSignId}) {
            if (_editingId != null) {
              notifier.stageUpdateVitalSign(
                vitalSignId: _editingId!,
                name: name,
                value: value,
                unit: unit,
                predefinedVitalSignId: predefinedVitalSignId,
              );
            } else {
              notifier.stageCreateVitalSign(
                name: name,
                value: value,
                unit: unit,
                predefinedVitalSignId: predefinedVitalSignId,
              );
            }
          },
        ),
      ],
    );
  }
}

class _EmptyVitalSignsState extends StatelessWidget {
  const _EmptyVitalSignsState({required this.canAddMore, required this.onAdd});

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
          border: Border.all(color: colors.borderDefault, style: BorderStyle.solid),
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
                  child: Icon(Icons.monitor_heart_outlined, size: 18, color: colors.textTertiary),
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'No vital signs recorded yet.',
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
                child: const Text('Add vital sign'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
