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
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_context.dart';
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
    return Row(
      crossAxisAlignment: expandField ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _complaintHistoryColumn(expandField: expandField)),
        const SizedBox(width: VisitPageTokens.sectionGap),
        Expanded(
          flex: 1,
          child: EncounterPhaseContext(
            visit: state.visit,
            canEdit: canEdit,
            safetyAxis: Axis.vertical,
            expandSafetySections: expandField,
          ),
        ),
      ],
    );
  }

  Widget _complaintHistoryColumn({required bool expandField}) {
    final complaint = _SubjectiveFieldCard(
      title: 'Complaint',
      expandBody: expandField,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.complaint},
        showSectionHeaders: false,
        expandField: expandField,
        showStaleBanner: true,
        showSaveBar: showClinicalNoteSaveBar,
        showEditButton: true,
      ),
    );

    final history = _SubjectiveFieldCard(
      title: 'History',
      expandBody: expandField,
      child: ClinicalNoteEditor(
        visitId: visitId,
        state: state,
        canEdit: canEdit,
        sections: const {ClinicalNoteSection.history},
        showSectionHeaders: false,
        expandField: expandField,
        showStaleBanner: false,
        showSaveBar: false,
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

    final contextVisit = visit ?? state?.visit;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SubjectiveFieldCard(
                title: 'Complaint',
                child: _SubjectiveDetailText(value: note?.complaint ?? ''),
              ),
              const SizedBox(height: VisitPageTokens.sectionGap),
              _SubjectiveFieldCard(
                title: 'History',
                child: _SubjectiveDetailText(value: note?.history ?? ''),
              ),
            ],
          ),
        ),
        if (contextVisit != null) ...[
          const SizedBox(width: VisitPageTokens.sectionGap),
          Expanded(
            flex: 1,
            child: EncounterPhaseContext(visit: contextVisit, safetyAxis: Axis.vertical),
          ),
        ],
      ],
    );
  }
}

class _SubjectiveFieldCard extends StatelessWidget {
  const _SubjectiveFieldCard({required this.title, required this.child, this.expandBody = false});

  final String title;
  final Widget child;
  final bool expandBody;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final colors = context.semanticColors;

    final body = Padding(
      padding: const EdgeInsets.fromLTRB(SpacingTokens.md, 0, SpacingTokens.md, SpacingTokens.md),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(context.shapeTokens.lg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: expandBody ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.md, SpacingTokens.md, SpacingTokens.md, SpacingTokens.md),
            child: Text(title, style: theme.title()),
          ),
          if (expandBody) Expanded(child: body) else body,
        ],
      ),
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
