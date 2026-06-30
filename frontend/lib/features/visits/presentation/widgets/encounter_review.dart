import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_context.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_result_capture_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_diagnosis_code_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_plan_details_form.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Read-only encounter summary with per-section edit links and submit (014 US4 / FR-018).
class EncounterReview extends StatelessWidget {
  const EncounterReview({
    required this.visitId,
    required this.visit,
    this.state,
    required this.canEdit,
    this.canUploadAttachments = false,
    this.onRefresh,
    this.onEditPhase,
    this.onSubmit,
    this.showSubmit = false,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final VisitDocumentationState? state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback? onRefresh;
  final ValueChanged<EncounterPhase>? onEditPhase;
  final VoidCallback? onSubmit;
  final bool showSubmit;

  String get _complaint => state?.complaint ?? visit.documentation?.complaint ?? '';
  String get _history => state?.history ?? visit.documentation?.history ?? '';
  String get _examination => state?.examination ?? visit.documentation?.examination ?? '';
  String get _diagnosis => state?.diagnosis ?? visit.documentation?.diagnosis ?? '';
  String get _plan => state?.plan ?? visit.documentation?.plan ?? '';

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('encounter_review'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EncounterPhaseHeader(
            phase: EncounterPhase.review,
            description: 'Read-only summary of the encounter — edit any section or submit when ready',
          ),
          _ReviewSection(
            phase: EncounterPhase.context,
            title: 'Context',
            canEdit: canEdit && onEditPhase != null,
            onEdit: onEditPhase == null ? null : () => onEditPhase!(EncounterPhase.context),
            child: EncounterPhaseContext(visit: visit, canEdit: canEdit),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          _ReviewSection(
            phase: EncounterPhase.subjective,
            title: 'Subjective',
            canEdit: canEdit && onEditPhase != null,
            onEdit: onEditPhase == null ? null : () => onEditPhase!(EncounterPhase.subjective),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VisitDetailField(label: 'Complaint', value: _complaint, abbr: 'C'),
                const SizedBox(height: SpacingTokens.sm),
                VisitDetailField(label: 'History', value: _history, abbr: 'H'),
              ],
            ),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          _ReviewSection(
            phase: EncounterPhase.objective,
            title: 'Objective',
            canEdit: canEdit && onEditPhase != null,
            onEdit: onEditPhase == null ? null : () => onEditPhase!(EncounterPhase.objective),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _VitalSignsSummary(vitalSigns: visit.vitalSigns),
                const SizedBox(height: SpacingTokens.sm),
                if (visit.pendingInvestigations.isNotEmpty) ...[
                  InvestigationResultCaptureList(
                    pendingInvestigations: visit.pendingInvestigations,
                    canEdit: canEdit,
                    onChanged: onRefresh ?? () {},
                  ),
                  const SizedBox(height: SpacingTokens.sm),
                ],
                VisitDetailField(label: 'Examination', value: _examination, abbr: 'E'),
              ],
            ),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          _ReviewSection(
            phase: EncounterPhase.assessment,
            title: 'Assessment',
            canEdit: canEdit && onEditPhase != null,
            onEdit: onEditPhase == null ? null : () => onEditPhase!(EncounterPhase.assessment),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VisitDetailField(label: 'Diagnosis', value: _diagnosis, abbr: 'A'),
                const SizedBox(height: SpacingTokens.sm),
                VisitDiagnosisCodeSummary(diagnosisCodes: visit.diagnosisCodes),
              ],
            ),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          _ReviewSection(
            phase: EncounterPhase.plan,
            title: 'Plan',
            canEdit: canEdit && onEditPhase != null,
            onEdit: onEditPhase == null ? null : () => onEditPhase!(EncounterPhase.plan),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VisitDetailField(label: 'Plan', value: _plan, abbr: 'P'),
                const SizedBox(height: SpacingTokens.md),
                VisitPlanDetailsSummary(planDetails: visit.planDetails),
                const SizedBox(height: SpacingTokens.md),
                _TreatmentPlansSummary(treatmentPlans: visit.treatmentPlans),
                const SizedBox(height: SpacingTokens.md),
                _InvestigationsSummary(investigations: visit.investigations),
                if (onRefresh != null) ...[
                  const SizedBox(height: SpacingTokens.md),
                  VisitAttachmentList(
                    visitId: visitId,
                    branchId: visit.branchId,
                    attachments: visit.attachments,
                    canUpload: canUploadAttachments,
                    onChanged: onRefresh!,
                    sectionKind: VisitPanelKind.attachment,
                    sectionTitle: 'Attachments',
                  ),
                ],
              ],
            ),
          ),
          if (showSubmit && onSubmit != null) ...[
            const SizedBox(height: VisitPageTokens.sectionGap),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: const Key('encounter_review_submit_button'),
                label: 'Submit visit',
                icon: const Icon(Icons.check_circle_outline, size: 18),
                onPressed: onSubmit,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.phase,
    required this.title,
    required this.child,
    required this.canEdit,
    this.onEdit,
  });

  final EncounterPhase phase;
  final String title;
  final Widget child;
  final bool canEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return VisitSectionCard(
      kind: VisitPanelKind.clinicalNote,
      title: title,
      headerActions: canEdit && onEdit != null
          ? [
              AppButton(
                key: Key('encounter_review_edit_${phase.name}'),
                label: 'Edit',
                variant: AppButtonVariant.ghost,
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: onEdit,
              ),
            ]
          : null,
      child: child,
    );
  }
}

class _VitalSignsSummary extends StatelessWidget {
  const _VitalSignsSummary({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    if (vitalSigns.isEmpty) {
      return const VisitEmptyHint(
        key: Key('encounter_review_vitals_empty'),
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

class _TreatmentPlansSummary extends StatelessWidget {
  const _TreatmentPlansSummary({required this.treatmentPlans});

  final List<TreatmentPlanItem> treatmentPlans;

  @override
  Widget build(BuildContext context) {
    if (treatmentPlans.isEmpty) {
      return const VisitEmptyHint(
        key: Key('encounter_review_treatment_plans_empty'),
        message: 'No treatment plans recorded.',
        icon: Icons.medication_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final plan in treatmentPlans)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: TreatmentPlanCardView(plan: plan),
          ),
      ],
    );
  }
}

class _InvestigationsSummary extends StatelessWidget {
  const _InvestigationsSummary({required this.investigations});

  final List<VisitInvestigation> investigations;

  @override
  Widget build(BuildContext context) {
    if (investigations.isEmpty) {
      return const VisitEmptyHint(
        key: Key('encounter_review_investigations_empty'),
        message: 'No investigations ordered.',
        icon: Icons.biotech_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final investigation in investigations)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: InvestigationCardView(investigation: investigation),
          ),
      ],
    );
  }
}
