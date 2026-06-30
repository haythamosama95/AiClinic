import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/bmi.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_result_capture_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Findings & Diagnosis phase — vitals, examination, and diagnosis (014 US2).
class EncounterPhaseObjective extends ConsumerWidget {
  const EncounterPhaseObjective({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.onRefresh,
    this.showClinicalNoteSaveBar = true,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final VoidCallback onRefresh;
  final bool showClinicalNoteSaveBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const Key('encounter_phase_objective'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VitalSignList(
            visitId: visitId,
            vitalSigns: state.visit.vitalSigns,
            predefinedVitalSigns: state.predefinedVitalSigns,
            canEdit: canEdit,
            onChanged: onRefresh,
            sectionKind: VisitPanelKind.vitalSigns,
            sectionTitle: 'Vital signs',
          ),
          PainScoreQuickEntry(
            visitId: visitId,
            vitalSigns: state.visit.vitalSigns,
            predefinedVitalSigns: state.predefinedVitalSigns,
            canEdit: canEdit,
            onChanged: onRefresh,
          ),
          BmiChip(vitalSigns: state.visit.vitalSigns),
          const SizedBox(height: VisitPageTokens.sectionGap),
          InvestigationResultCaptureList(
            pendingInvestigations: state.visit.pendingInvestigations,
            canEdit: canEdit,
            onChanged: onRefresh,
          ),
          if (state.visit.pendingInvestigations.isNotEmpty) const SizedBox(height: VisitPageTokens.sectionGap),
          VisitSectionCard(
            kind: VisitPanelKind.examination,
            title: 'Examination',
            child: ClinicalNoteEditor(
              visitId: visitId,
              state: state,
              canEdit: canEdit,
              sections: const {ClinicalNoteSection.examination},
              showStaleBanner: false,
              showSaveBar: showClinicalNoteSaveBar,
            ),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          VisitSectionCard(
            kind: VisitPanelKind.diagnosis,
            title: 'Diagnosis',
            child: ClinicalNoteEditor(
              visitId: visitId,
              state: state,
              canEdit: canEdit,
              sections: const {ClinicalNoteSection.diagnosis},
              showStaleBanner: false,
              showSaveBar: showClinicalNoteSaveBar,
            ),
          ),
        ],
      ),
    );
  }
}

/// Derived BMI chip — client-side only (FR-025).
class BmiChip extends StatelessWidget {
  const BmiChip({required this.vitalSigns, super.key});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final bmi = deriveBmiFromVitalSigns(vitalSigns);
    if (bmi == null) {
      return const SizedBox.shrink();
    }

    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(top: SpacingTokens.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          key: const Key('encounter_objective_bmi_chip'),
          decoration: BoxDecoration(
            color: theme.pulse.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(theme.tileRadius),
            border: Border.all(color: theme.pulse.withValues(alpha: 0.24)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed_outlined, size: 16, color: theme.pulseDeep),
                const SizedBox(width: SpacingTokens.sm),
                Text('BMI ${bmi.displayValue}', style: theme.bodyStrong(color: theme.pulseDeep)),
                const SizedBox(width: SpacingTokens.sm),
                Text(
                  '(${bmi.heightCm.toStringAsFixed(0)} cm · ${bmi.weightKg.toStringAsFixed(0)} kg)',
                  style: theme.caption(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Objective content for the detail view.
class EncounterPhaseObjectiveDetail extends StatelessWidget {
  const EncounterPhaseObjectiveDetail({
    required this.visitId,
    required this.visit,
    required this.canEdit,
    required this.onRefresh,
    this.docState,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final bool canEdit;
  final VoidCallback onRefresh;
  final VisitDocumentationState? docState;

  @override
  Widget build(BuildContext context) {
    if (canEdit && docState != null) {
      return EncounterPhaseObjective(visitId: visitId, state: docState!, canEdit: true, onRefresh: onRefresh);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitSectionCard(
          kind: VisitPanelKind.vitalSigns,
          title: 'Vital signs',
          child: _VitalSignsReadOnly(vitalSigns: visit.vitalSigns),
        ),
        BmiChip(vitalSigns: visit.vitalSigns),
        if (visit.pendingInvestigations.isNotEmpty) ...[
          const SizedBox(height: VisitPageTokens.sectionGap),
          InvestigationResultCaptureList(
            pendingInvestigations: visit.pendingInvestigations,
            canEdit: false,
            onChanged: onRefresh,
          ),
        ],
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitSectionCard(
          kind: VisitPanelKind.examination,
          title: 'Examination',
          child: EncounterPhaseExaminationFromVisit(note: visit.documentation),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitSectionCard(
          kind: VisitPanelKind.diagnosis,
          title: 'Diagnosis',
          child: EncounterPhaseDiagnosisFromVisit(note: visit.documentation),
        ),
      ],
    );
  }
}

class EncounterPhaseExaminationFromVisit extends StatelessWidget {
  const EncounterPhaseExaminationFromVisit({required this.note, super.key});

  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: 'Examination', value: note?.examination ?? '', abbr: 'E');
  }
}

class EncounterPhaseDiagnosisFromVisit extends StatelessWidget {
  const EncounterPhaseDiagnosisFromVisit({required this.note, super.key});

  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: 'Diagnosis', value: note?.diagnosis ?? '', abbr: 'D');
  }
}

class _VitalSignsReadOnly extends StatelessWidget {
  const _VitalSignsReadOnly({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    if (vitalSigns.isEmpty) {
      return const VisitEmptyHint(
        key: Key('visit_detail_vital_signs_empty'),
        message: 'No vital signs recorded.',
        icon: Icons.monitor_heart_outlined,
      );
    }

    return Wrap(
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.sm,
      children: [for (final sign in vitalSigns) VitalSignCardView(sign: sign)],
    );
  }
}
