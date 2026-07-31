import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_entry_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/medical_background_form_dialog.dart';

enum MedicalBackgroundCategory { conditions, allergies, medications }

typedef MedicalBackgroundCreateHandler = void Function(String title, String? note);
typedef MedicalBackgroundUpdateHandler = void Function(String id, String title, String? note);
typedef MedicalBackgroundArchiveHandler = void Function(String id);

/// Chronic conditions, allergies, and current medications for the intake step.
class VisitMedicalBackgroundEditor extends StatelessWidget {
  const VisitMedicalBackgroundEditor({
    required this.chronicConditions,
    required this.allergies,
    required this.currentMedications,
    required this.onCreateCondition,
    required this.onUpdateCondition,
    required this.onArchiveCondition,
    required this.onCreateAllergy,
    required this.onUpdateAllergy,
    required this.onArchiveAllergy,
    required this.onCreateMedication,
    required this.onUpdateMedication,
    required this.onArchiveMedication,
    this.canEdit = true,
    super.key,
  });

  final List<PatientChronicCondition> chronicConditions;
  final List<PatientAllergy> allergies;
  final List<PatientMedication> currentMedications;
  final MedicalBackgroundCreateHandler onCreateCondition;
  final MedicalBackgroundUpdateHandler onUpdateCondition;
  final MedicalBackgroundArchiveHandler onArchiveCondition;
  final MedicalBackgroundCreateHandler onCreateAllergy;
  final MedicalBackgroundUpdateHandler onUpdateAllergy;
  final MedicalBackgroundArchiveHandler onArchiveAllergy;
  final MedicalBackgroundCreateHandler onCreateMedication;
  final MedicalBackgroundUpdateHandler onUpdateMedication;
  final MedicalBackgroundArchiveHandler onArchiveMedication;
  final bool canEdit;

  static const _categories = <_CategorySpec>[
    _CategorySpec(
      category: MedicalBackgroundCategory.conditions,
      label: 'Chronic conditions',
      helperText: 'Active diagnoses and long-term conditions.',
      accent: MedicalBackgroundAccent.warning,
      dialogTitle: 'Add chronic condition',
      dialogDescription: 'Record a condition and any context relevant to this visit.',
      itemLabel: 'Condition',
      noteLabel: 'Clinical note',
      itemPlaceholder: 'e.g. Type 2 diabetes',
      notePlaceholder: 'e.g. Diagnosed 2019 · well controlled on metformin…',
      editDialogTitle: 'Edit chronic condition',
    ),
    _CategorySpec(
      category: MedicalBackgroundCategory.allergies,
      label: 'Allergies',
      helperText: 'Drug, food, and environmental allergies.',
      accent: MedicalBackgroundAccent.danger,
      dialogTitle: 'Add allergy',
      dialogDescription: 'Record an allergen and describe the reaction for this encounter.',
      itemLabel: 'Allergy',
      noteLabel: 'Reaction note',
      itemPlaceholder: 'e.g. Penicillin',
      notePlaceholder: 'e.g. Anaphylaxis · avoid all beta-lactams…',
      editDialogTitle: 'Edit allergy',
    ),
    _CategorySpec(
      category: MedicalBackgroundCategory.medications,
      label: 'Current medications',
      helperText: 'Medications the patient is taking at the time of visit.',
      accent: MedicalBackgroundAccent.info,
      dialogTitle: 'Add medication',
      dialogDescription: 'Record a medication and how the patient is taking it.',
      itemLabel: 'Medication',
      noteLabel: 'Dosing note',
      itemPlaceholder: 'e.g. Metformin',
      notePlaceholder: 'e.g. 500 mg twice daily · good adherence…',
      editDialogTitle: 'Edit medication',
    ),
  ];

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
            Text('Medical background', style: AppTypography.title(context).copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Chronic conditions, allergies, and current medications relevant to this visit.',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.space5),
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                if (!isWide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < _categories.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.space5),
                        _CategoryColumn(
                          spec: _categories[i],
                          entries: _entriesFor(_categories[i].category),
                          canEdit: canEdit,
                          onAdd: () => _openAddDialog(context, _categories[i]),
                          onEdit: (entry) => _openEditDialog(context, _categories[i], entry),
                          onRemove: (entry) => _archiveEntry(_categories[i].category, entry.id),
                        ),
                      ],
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _categories.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.space4),
                      Expanded(
                        child: _CategoryColumn(
                          spec: _categories[i],
                          entries: _entriesFor(_categories[i].category),
                          canEdit: canEdit,
                          onAdd: () => _openAddDialog(context, _categories[i]),
                          onEdit: (entry) => _openEditDialog(context, _categories[i], entry),
                          onRemove: (entry) => _archiveEntry(_categories[i].category, entry.id),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<_DisplayEntry> _entriesFor(MedicalBackgroundCategory category) {
    return switch (category) {
      MedicalBackgroundCategory.conditions => [
        for (final item in chronicConditions) _DisplayEntry(id: item.id, title: item.name, note: item.note),
      ],
      MedicalBackgroundCategory.allergies => [
        for (final item in allergies) _DisplayEntry(id: item.id, title: item.substance, note: item.reaction),
      ],
      MedicalBackgroundCategory.medications => [
        for (final item in currentMedications) _DisplayEntry(id: item.id, title: item.name, note: item.note),
      ],
    };
  }

  Future<void> _openAddDialog(BuildContext context, _CategorySpec spec) async {
    final result = await MedicalBackgroundFormDialog.show(
      context,
      dialogTitle: spec.dialogTitle,
      dialogDescription: spec.dialogDescription,
      itemLabel: spec.itemLabel,
      noteLabel: spec.noteLabel,
      itemPlaceholder: spec.itemPlaceholder,
      notePlaceholder: spec.notePlaceholder,
    );
    if (result == null) {
      return;
    }
    _createEntry(spec.category, result.title, result.note);
  }

  Future<void> _openEditDialog(BuildContext context, _CategorySpec spec, _DisplayEntry entry) async {
    final result = await MedicalBackgroundFormDialog.show(
      context,
      dialogTitle: spec.editDialogTitle,
      dialogDescription: spec.dialogDescription,
      itemLabel: spec.itemLabel,
      noteLabel: spec.noteLabel,
      itemPlaceholder: spec.itemPlaceholder,
      notePlaceholder: spec.notePlaceholder,
      initialTitle: entry.title,
      initialNote: entry.note,
    );
    if (result == null) {
      return;
    }
    _updateEntry(spec.category, entry.id, result.title, result.note);
  }

  void _createEntry(MedicalBackgroundCategory category, String title, String? note) {
    switch (category) {
      case MedicalBackgroundCategory.conditions:
        onCreateCondition(title, note);
      case MedicalBackgroundCategory.allergies:
        onCreateAllergy(title, note);
      case MedicalBackgroundCategory.medications:
        onCreateMedication(title, note);
    }
  }

  void _updateEntry(MedicalBackgroundCategory category, String id, String title, String? note) {
    switch (category) {
      case MedicalBackgroundCategory.conditions:
        onUpdateCondition(id, title, note);
      case MedicalBackgroundCategory.allergies:
        onUpdateAllergy(id, title, note);
      case MedicalBackgroundCategory.medications:
        onUpdateMedication(id, title, note);
    }
  }

  void _archiveEntry(MedicalBackgroundCategory category, String id) {
    switch (category) {
      case MedicalBackgroundCategory.conditions:
        onArchiveCondition(id);
      case MedicalBackgroundCategory.allergies:
        onArchiveAllergy(id);
      case MedicalBackgroundCategory.medications:
        onArchiveMedication(id);
    }
  }
}

class _DisplayEntry {
  const _DisplayEntry({required this.id, required this.title, this.note});

  final String id;
  final String title;
  final String? note;
}

class _CategorySpec {
  const _CategorySpec({
    required this.category,
    required this.label,
    required this.helperText,
    required this.accent,
    required this.dialogTitle,
    required this.dialogDescription,
    required this.itemLabel,
    required this.noteLabel,
    required this.itemPlaceholder,
    required this.notePlaceholder,
    required this.editDialogTitle,
  });

  final MedicalBackgroundCategory category;
  final String label;
  final String helperText;
  final MedicalBackgroundAccent accent;
  final String dialogTitle;
  final String dialogDescription;
  final String itemLabel;
  final String noteLabel;
  final String itemPlaceholder;
  final String notePlaceholder;
  final String editDialogTitle;
}

class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.spec,
    required this.entries,
    required this.canEdit,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final _CategorySpec spec;
  final List<_DisplayEntry> entries;
  final bool canEdit;
  final VoidCallback onAdd;
  final ValueChanged<_DisplayEntry> onEdit;
  final ValueChanged<_DisplayEntry> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(spec.label, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
            const SizedBox(width: AppSpacing.space1),
            AppTooltip(
              message: spec.helperText,
              preferBelow: false,
              child: Semantics(
                button: true,
                label: 'More about ${spec.label}',
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
        ),
        const SizedBox(height: AppSpacing.space3),
        if (entries.isEmpty)
          _EmptyCategoryState(spec: spec, canEdit: canEdit, onAdd: onAdd)
        else ...[
          for (final entry in entries) ...[
            MedicalBackgroundEntryCard(
              title: entry.title,
              note: entry.note,
              accent: spec.accent,
              canEdit: canEdit,
              onEdit: () => onEdit(entry),
              onRemove: () => onRemove(entry),
            ),
            const SizedBox(height: AppSpacing.space2),
          ],
          if (canEdit)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: const Icon(Icons.add_rounded, size: 16),
                onPressed: onAdd,
                child: const Text('Add'),
              ),
            ),
        ],
      ],
    );
  }
}

class _EmptyCategoryState extends StatelessWidget {
  const _EmptyCategoryState({required this.spec, required this.canEdit, required this.onAdd});

  final _CategorySpec spec;
  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accentSurface = switch (spec.accent) {
      MedicalBackgroundAccent.warning => colors.statusWarningSurface,
      MedicalBackgroundAccent.danger => colors.statusDangerSurface,
      MedicalBackgroundAccent.info => colors.statusInfoSurface,
    };
    final accentFg = switch (spec.accent) {
      MedicalBackgroundAccent.warning => colors.statusWarningFg,
      MedicalBackgroundAccent.danger => colors.statusDangerFg,
      MedicalBackgroundAccent.info => colors.statusInfoFg,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault, style: BorderStyle.solid),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space5),
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: accentSurface, shape: BoxShape.circle),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space2),
                child: Icon(_iconFor(spec.category), size: 18, color: accentFg),
              ),
            ),
            const SizedBox(height: AppSpacing.space3),
            Text(
              'Nothing documented yet',
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
                child: const Text('Add'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(MedicalBackgroundCategory category) {
    return switch (category) {
      MedicalBackgroundCategory.conditions => Icons.monitor_heart_outlined,
      MedicalBackgroundCategory.allergies => Icons.warning_amber_rounded,
      MedicalBackgroundCategory.medications => Icons.medication_outlined,
    };
  }
}
