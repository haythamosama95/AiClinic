import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Presents a two-option stale-documentation conflict resolution dialog.
///
/// Returns `true` to keep the local draft, `false` to load the server copy,
/// or `null` when the user cancels.
Future<bool?> showVisitStaleConflictDialog(
  BuildContext context, {
  required VisitClinicalNote serverNote,
  required VisitClinicalNote localNote,
}) {
  final l10n = context.l10n;

  return AppDialog.show<bool>(
    context,
    title: l10n.visitStaleConflictTitle,
    description: l10n.visitStaleConflictDescription,
    size: AppDialogSize.lg,
    barrierDismissible: false,
    footer: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop<bool?>(null),
          child: Text(l10n.cancel),
        ),
        const SizedBox(width: AppSpacing.space2),
        AppButton(
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.visitStaleConflictLoadTheirs),
        ),
        const SizedBox(width: AppSpacing.space2),
        AppButton(
          variant: AppButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.visitStaleConflictKeepMine),
        ),
      ],
    ),
    child: _VisitClinicalNoteComparison(serverNote: serverNote, localNote: localNote),
  );
}

class _VisitClinicalNoteComparison extends StatelessWidget {
  const _VisitClinicalNoteComparison({required this.serverNote, required this.localNote});

  final VisitClinicalNote serverNote;
  final VisitClinicalNote localNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 640;

        final serverColumn = _ClinicalNoteColumn(
          title: l10n.visitStaleConflictServerVersion,
          note: serverNote,
        );
        final localColumn = _ClinicalNoteColumn(
          title: l10n.visitStaleConflictYourVersion,
          note: localNote,
        );

        if (useSideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: serverColumn),
              const SizedBox(width: AppSpacing.space4),
              Expanded(child: localColumn),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            serverColumn,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.space4),
              child: Divider(color: colors.borderSubtle),
            ),
            localColumn,
          ],
        );
      },
    );
  }
}

class _ClinicalNoteColumn extends StatelessWidget {
  const _ClinicalNoteColumn({required this.title, required this.note});

  final String title;
  final VisitClinicalNote note;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.75)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
            const SizedBox(height: AppSpacing.space3),
            for (final section in ClinicalNoteSection.values) ...[
              _ClinicalNoteSectionBlock(section: section, value: _sectionValue(note, section)),
              if (section != ClinicalNoteSection.values.last) const SizedBox(height: AppSpacing.space3),
            ],
          ],
        ),
      ),
    );
  }

  String? _sectionValue(VisitClinicalNote note, ClinicalNoteSection section) {
    return switch (section) {
      ClinicalNoteSection.complaint => note.complaint,
      ClinicalNoteSection.history => note.history,
      ClinicalNoteSection.examination => note.examination,
      ClinicalNoteSection.diagnosis => note.diagnosis,
      ClinicalNoteSection.plan => note.plan,
    };
  }
}

class _ClinicalNoteSectionBlock extends StatelessWidget {
  const _ClinicalNoteSectionBlock({required this.section, required this.value});

  final ClinicalNoteSection section;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;
    final text = value?.trim();
    final display = (text == null || text.isEmpty) ? l10n.visitStaleConflictSectionEmpty : text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _sectionLabel(l10n, section),
          style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: AppSpacing.space1),
        Text(
          display,
          style: AppTypography.bodySm(context).copyWith(
            color: text == null || text.isEmpty ? colors.textTertiary : colors.textPrimary,
            fontStyle: text == null || text.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ],
    );
  }

  String _sectionLabel(AppLocalizations l10n, ClinicalNoteSection section) {
    return switch (section) {
      ClinicalNoteSection.complaint => l10n.visitClinicalSectionComplaint,
      ClinicalNoteSection.history => l10n.visitClinicalSectionHistory,
      ClinicalNoteSection.examination => l10n.visitClinicalSectionExamination,
      ClinicalNoteSection.diagnosis => l10n.visitClinicalSectionDiagnosis,
      ClinicalNoteSection.plan => l10n.visitClinicalSectionPlan,
    };
  }
}
