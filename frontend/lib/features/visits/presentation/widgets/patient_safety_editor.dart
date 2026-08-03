import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/allergy_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/condition_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medication_form_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_entry_list.dart';

/// Patient safety list kind handled by [PatientSafetyEditor].
enum PatientSafetyKind { allergy, medication, condition }

/// Generic editor for allergies, medications, or chronic conditions.
class PatientSafetyEditor extends ConsumerStatefulWidget {
  const PatientSafetyEditor({
    required this.visitId,
    required this.patientId,
    required this.kind,
    super.key,
  });

  final String visitId;
  final String patientId;
  final PatientSafetyKind kind;

  @override
  ConsumerState<PatientSafetyEditor> createState() => _PatientSafetyEditorState();
}

class _PatientSafetyEditorState extends ConsumerState<PatientSafetyEditor> {
  var _dialogOpen = false;
  String? _editingId;

  _PatientSafetyCopy get _copy => _copyFor(widget.kind);

  bool get _canEdit {
    final doc = ref.watch(visitDocumentationProvider(widget.visitId)).value;
    if (doc == null) {
      return false;
    }
    return doc.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());
  }

  PatientSafetyContext? get _effectiveSafety {
    final doc = ref.watch(visitDocumentationProvider(widget.visitId)).value;
    final base = ref.watch(patientSafetyProvider(widget.patientId)).value;
    if (doc == null || base == null) {
      return null;
    }
    return doc.effectivePatientSafety(base);
  }

  void _openCreateDialog() {
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

  void _closeDialog() {
    setState(() {
      _dialogOpen = false;
      _editingId = null;
    });
  }

  void _archive(String id) {
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    switch (widget.kind) {
      case PatientSafetyKind.allergy:
        notifier.stageArchiveAllergy(id);
      case PatientSafetyKind.medication:
        notifier.stageArchiveMedication(id);
      case PatientSafetyKind.condition:
        notifier.stageArchiveCondition(id);
    }
  }

  PatientAllergy? _findAllergy(String id) {
    return _effectiveSafety?.allergies.where((item) => item.id == id).firstOrNull;
  }

  PatientMedication? _findMedication(String id) {
    return _effectiveSafety?.currentMedications.where((item) => item.id == id).firstOrNull;
  }

  PatientChronicCondition? _findCondition(String id) {
    return _effectiveSafety?.chronicConditions.where((item) => item.id == id).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final safetyAsync = ref.watch(patientSafetyProvider(widget.patientId));
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));

    return safetyAsync.when(
      loading: () => const SizedBox(height: 120, child: Center(child: AppProgress())),
      error: (error, _) => Text(
        'Unable to load ${_copy.label.toLowerCase()}.',
        style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg),
      ),
      data: (_) {
        return docAsync.when(
          loading: () => const SizedBox(height: 120, child: Center(child: AppProgress())),
          error: (error, _) => Text(
            'Unable to load visit documentation.',
            style: AppTypography.caption(context).copyWith(color: colors.statusDangerFg),
          ),
          data: (_) {
            final effective = _effectiveSafety;
            if (effective == null) {
              return const SizedBox.shrink();
            }

            final items = switch (widget.kind) {
              PatientSafetyKind.allergy => effective.allergies,
              PatientSafetyKind.medication => effective.currentMedications,
              PatientSafetyKind.condition => effective.chronicConditions,
            };

            if (items.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionTitle(label: _copy.label, hint: _copy.helperText),
                  const SizedBox(height: AppSpacing.space3),
                  _PatientSafetyEmptyState(
                    icon: _copy.emptyIcon,
                    message: _copy.emptyMessage,
                    addLabel: _copy.addLabel,
                    canEdit: _canEdit,
                    onAdd: _openCreateDialog,
                  ),
                  ..._buildDialog(),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionTitle(label: _copy.label, hint: _copy.helperText),
                const SizedBox(height: AppSpacing.space3),
                _buildList(context, effective),
                if (_canEdit) ...[
                  const SizedBox(height: AppSpacing.space3),
                  _buildAddButton(),
                ],
                ..._buildDialog(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildList(BuildContext context, PatientSafetyContext effective) {
    return switch (widget.kind) {
      PatientSafetyKind.allergy => _buildAllergyList(context, effective.allergies),
      PatientSafetyKind.medication => _buildMedicationList(context, effective.currentMedications),
      PatientSafetyKind.condition => _buildConditionList(context, effective.chronicConditions),
    };
  }

  Widget _buildAllergyList(BuildContext context, List<PatientAllergy> items) {
    return VisitEntryList<PatientAllergy>(
      items: items,
      itemId: (item) => item.id,
      itemBuilder: (context, allergy) => _PatientSafetyItemCard(
        title: allergy.substance,
        subtitle: allergy.reaction,
        onEdit: _canEdit ? () => _openEditDialog(allergy.id) : null,
        onRemove: _canEdit ? () => _archive(allergy.id) : null,
        editLabel: 'Edit allergy',
        removeLabel: 'Remove allergy',
      ),
    );
  }

  Widget _buildMedicationList(BuildContext context, List<PatientMedication> items) {
    return VisitEntryList<PatientMedication>(
      items: items,
      itemId: (item) => item.id,
      itemBuilder: (context, medication) => _PatientSafetyItemCard(
        title: medication.name,
        subtitle: medication.note,
        onEdit: _canEdit ? () => _openEditDialog(medication.id) : null,
        onRemove: _canEdit ? () => _archive(medication.id) : null,
        editLabel: 'Edit medication',
        removeLabel: 'Remove medication',
      ),
    );
  }

  Widget _buildConditionList(BuildContext context, List<PatientChronicCondition> items) {
    return VisitEntryList<PatientChronicCondition>(
      items: items,
      itemId: (item) => item.id,
      itemBuilder: (context, condition) => _PatientSafetyItemCard(
        title: condition.name,
        subtitle: condition.note,
        onEdit: _canEdit ? () => _openEditDialog(condition.id) : null,
        onRemove: _canEdit ? () => _archive(condition.id) : null,
        editLabel: 'Edit condition',
        removeLabel: 'Remove condition',
      ),
    );
  }

  Widget _buildAddButton() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: AppButton(
        variant: AppButtonVariant.secondary,
        size: AppButtonSize.sm,
        leadingIcon: const Icon(Icons.add, size: 14),
        onPressed: _openCreateDialog,
        child: Text(_copy.addAnotherLabel),
      ),
    );
  }

  List<Widget> _buildDialog() {
    return switch (widget.kind) {
      PatientSafetyKind.allergy => [
        AllergyFormDialog(
          open: _dialogOpen,
          onOpenChange: (open) {
            if (!open) {
              _closeDialog();
            } else {
              setState(() => _dialogOpen = true);
            }
          },
          visitId: widget.visitId,
          editing: _editingId == null ? null : _findAllergy(_editingId!),
        ),
      ],
      PatientSafetyKind.medication => [
        MedicationFormDialog(
          open: _dialogOpen,
          onOpenChange: (open) {
            if (!open) {
              _closeDialog();
            } else {
              setState(() => _dialogOpen = true);
            }
          },
          visitId: widget.visitId,
          editing: _editingId == null ? null : _findMedication(_editingId!),
        ),
      ],
      PatientSafetyKind.condition => [
        ConditionFormDialog(
          open: _dialogOpen,
          onOpenChange: (open) {
            if (!open) {
              _closeDialog();
            } else {
              setState(() => _dialogOpen = true);
            }
          },
          visitId: widget.visitId,
          editing: _editingId == null ? null : _findCondition(_editingId!),
        ),
      ],
    };
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.hint});

  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      children: [
        Text(label, style: AppTypography.title(context)),
        const SizedBox(width: AppSpacing.space2),
        AppTooltip(
          message: hint,
          preferBelow: false,
          child: Semantics(
            button: true,
            label: 'More about $label',
            child: IconButton(
              onPressed: () {},
              icon: Icon(Icons.help_outline, size: 16, color: colors.iconMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 20, height: 20),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PatientSafetyEmptyState extends StatelessWidget {
  const _PatientSafetyEmptyState({
    required this.icon,
    required this.message,
    required this.addLabel,
    required this.canEdit,
    required this.onAdd,
  });

  final IconData icon;
  final String message;
  final String addLabel;
  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderDefault, style: BorderStyle.solid),
        color: colors.surfaceMuted.withValues(alpha: 0.4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space3),
                child: Icon(icon, size: 18, color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              message,
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (canEdit) ...[
              const SizedBox(height: AppSpacing.space4),
              AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: const Icon(Icons.add, size: 14),
                onPressed: onAdd,
                child: Text(addLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatientSafetyItemCard extends StatelessWidget {
  const _PatientSafetyItemCard({
    required this.title,
    required this.onEdit,
    required this.onRemove,
    required this.editLabel,
    required this.removeLabel,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final String editLabel;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final resolvedSubtitle = subtitle?.trim();

    return VisitEntryCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySm(context).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (resolvedSubtitle != null && resolvedSubtitle.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.space05),
                  Text(
                    resolvedSubtitle,
                    style: AppTypography.caption(context).copyWith(color: colors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null && onRemove != null)
            VisitEntryCardIconActions(
              onEdit: onEdit!,
              onRemove: onRemove!,
              editLabel: editLabel,
              removeLabel: removeLabel,
            ),
        ],
      ),
    );
  }
}

class _PatientSafetyCopy {
  const _PatientSafetyCopy({
    required this.label,
    required this.helperText,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.addLabel,
    required this.addAnotherLabel,
  });

  final String label;
  final String helperText;
  final IconData emptyIcon;
  final String emptyMessage;
  final String addLabel;
  final String addAnotherLabel;
}

_PatientSafetyCopy _copyFor(PatientSafetyKind kind) {
  return switch (kind) {
    PatientSafetyKind.allergy => const _PatientSafetyCopy(
      label: 'Allergies',
      helperText: 'Drug, food, and environmental allergies.',
      emptyIcon: Icons.warning_amber_outlined,
      emptyMessage: 'No allergies recorded yet.',
      addLabel: 'Add allergy',
      addAnotherLabel: 'Add another allergy',
    ),
    PatientSafetyKind.medication => const _PatientSafetyCopy(
      label: 'Current medications',
      helperText: 'Medications the patient is taking at the time of visit.',
      emptyIcon: Icons.medication_outlined,
      emptyMessage: 'No medications recorded yet.',
      addLabel: 'Add medication',
      addAnotherLabel: 'Add another medication',
    ),
    PatientSafetyKind.condition => const _PatientSafetyCopy(
      label: 'Chronic conditions',
      helperText: 'Active diagnoses and long-term conditions.',
      emptyIcon: Icons.favorite_outline,
      emptyMessage: 'No chronic conditions recorded yet.',
      addLabel: 'Add condition',
      addAnotherLabel: 'Add another condition',
    ),
  };
}
