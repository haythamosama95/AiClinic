import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/shape_tokens.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/patient_health_tracking_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Subjective phase — Complaint, History, and patient context (014 US2).
class EncounterPhaseSubjective extends ConsumerWidget {
  const EncounterPhaseSubjective({
    required this.visitId,
    required this.state,
    required this.canEdit,
    this.showClinicalNoteSaveBar = true,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool showClinicalNoteSaveBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const Key('encounter_phase_subjective'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandField = constraints.hasBoundedHeight && constraints.maxHeight.isFinite;
          if (expandField) {
            return SizedBox(height: constraints.maxHeight, child: _buildIntakeLayout(expandField: true));
          }
          return _buildIntakeLayout(expandField: false);
        },
      ),
    );
  }

  Widget _buildIntakeLayout({required bool expandField}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;
        final intakeColumn = _complaintHistoryColumn(expandField: expandField);

        final healthCard = PatientHealthTrackingCard(
          patientId: state.visit.patientId,
          canEdit: canEdit,
          expandBody: expandField,
        );

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              intakeColumn,
              const SizedBox(height: VisitPageTokens.sectionGap),
              healthCard,
            ],
          );
        }

        if (!expandField) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: intakeColumn),
              const SizedBox(width: VisitPageTokens.sectionGap),
              Expanded(flex: 2, child: healthCard),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: intakeColumn),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(flex: 2, child: healthCard),
          ],
        );
      },
    );
  }

  Widget _complaintHistoryColumn({required bool expandField}) {
    final complaint = _SubjectiveFieldCard(
      title: 'Complaint',
      titleIcon: Icons.speaker_notes_outlined,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.complaint},
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: true,
        showSaveBar: showClinicalNoteSaveBar,
        showEditButton: true,
        toolbarLeading: _SubjectiveToolbarTitle(title: 'Complaint', icon: Icons.speaker_notes_outlined),
        emptyStateIcon: Icons.speaker_notes_outlined,
        emptyStateText: 'Start entering the complaint',
      ),
    );

    final history = _SubjectiveFieldCard(
      title: 'History',
      titleIcon: Icons.history_outlined,
      expandBody: expandField,
      embedTitleInToolbar: true,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.history},
        showSectionHeaders: false,
        expandField: expandField,
        useRichTextParagraph: true,
        removeBorder: true,
        showStaleBanner: false,
        showSaveBar: false,
        toolbarLeading: _SubjectiveToolbarTitle(title: 'History', icon: Icons.history_outlined),
        emptyStateIcon: Icons.history_outlined,
        emptyStateText: 'Start entering the history',
      ),
    );

    if (!expandField) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          complaint,
          const SizedBox(height: VisitPageTokens.sectionGap),
          history,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: complaint),
        const SizedBox(height: VisitPageTokens.sectionGap),
        Expanded(child: history),
      ],
    );
  }
}

/// Subjective content for the detail view.
class EncounterPhaseSubjectiveDetail extends StatelessWidget {
  const EncounterPhaseSubjectiveDetail({
    required this.visitId,
    required this.state,
    required this.canEdit,
    this.note,
    this.visit,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState? state;
  final bool canEdit;
  final VisitClinicalNote? note;
  final VisitDetail? visit;

  @override
  Widget build(BuildContext context) {
    if (canEdit && state != null) {
      return EncounterPhaseSubjective(visitId: visitId, state: state!, canEdit: true);
    }

    final patientId = visit?.patientId;
    final readOnlyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubjectiveFieldCard(
          title: 'Complaint',
          titleIcon: Icons.speaker_notes_outlined,
          child: _SubjectiveDetailText(value: note?.complaint ?? ''),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        _SubjectiveFieldCard(
          title: 'History',
          titleIcon: Icons.history_outlined,
          child: _SubjectiveDetailText(value: note?.history ?? ''),
        ),
      ],
    );

    if (patientId == null || patientId.isEmpty) {
      return readOnlyColumn;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useSideBySide = constraints.maxWidth >= 900;
        final healthCard = PatientHealthTrackingCard(patientId: patientId, canEdit: false);

        if (!useSideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              readOnlyColumn,
              const SizedBox(height: VisitPageTokens.sectionGap),
              healthCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: readOnlyColumn),
            const SizedBox(width: VisitPageTokens.sectionGap),
            Expanded(flex: 2, child: healthCard),
          ],
        );
      },
    );
  }
}

class _SubjectiveFieldCard extends StatelessWidget {
  const _SubjectiveFieldCard({
    required this.title,
    required this.titleIcon,
    required this.child,
    this.expandBody = false,
    this.embedTitleInToolbar = false,
  });

  final String title;
  final IconData titleIcon;
  final Widget child;
  final bool expandBody;
  final bool embedTitleInToolbar;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final colors = context.semanticColors;
    final borderRadius = BorderRadius.circular(context.shapeTokens.lg);

    final bodyPadding = embedTitleInToolbar
        ? const EdgeInsets.all(SpacingTokens.md)
        : const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md);

    final body = Padding(padding: bodyPadding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: borderRadius,
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(gradient: theme.pulseCardGradient)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
              children: [
                if (!embedTitleInToolbar)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.md,
                      SpacingTokens.md,
                    ),
                    child: Row(
                      spacing: SpacingTokens.sm,
                      children: [
                        Icon(titleIcon, size: 20, color: theme.pulse),
                        Text(title, style: theme.title()),
                      ],
                    ),
                  ),
                if (expandBody) Expanded(child: body) else body,
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectiveToolbarTitle extends StatelessWidget {
  const _SubjectiveToolbarTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: SpacingTokens.sm,
      children: [
        Icon(icon, size: 20, color: theme.pulse),
        Text(title, style: theme.title()),
      ],
    );
  }
}

class _SubjectiveDetailText extends StatelessWidget {
  const _SubjectiveDetailText({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final display = value.trim().isEmpty ? '—' : value.trim();
    final isEmpty = value.trim().isEmpty;

    return Text(display, style: theme.body(color: isEmpty ? theme.mutedInk : theme.ink));
  }
}
