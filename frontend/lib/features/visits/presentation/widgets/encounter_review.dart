import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/clinical_note_section.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_result_capture_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Read-only encounter summary with per-section edit links and submit (014 US4 / FR-018).
class EncounterReview extends ConsumerWidget {
  const EncounterReview({
    required this.visitId,
    required this.visit,
    this.state,
    required this.canEdit,
    this.canUploadAttachments = false,
    this.onRefresh,
    this.onEditPhase,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final VisitDocumentationState? state;
  final bool canEdit;
  final bool canUploadAttachments;
  final VoidCallback? onRefresh;
  final ValueChanged<EncounterPhase>? onEditPhase;

  List<dynamic>? _richDelta(VisitDocumentationState? docState, ClinicalNoteSection section) =>
      docState?.richTextDrafts[section];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docState = ref.watch(visitDocumentationProvider(visitId)).asData?.value ?? state;
    final effectiveVisit = docState?.effectiveVisit ?? visit;

    final complaint = docState?.complaint ?? visit.documentation?.complaint ?? '';
    final history = docState?.history ?? visit.documentation?.history ?? '';
    final examination = docState?.examination ?? visit.documentation?.examination ?? '';
    final diagnosis = docState?.diagnosis ?? visit.documentation?.diagnosis ?? '';
    final plan = docState?.plan ?? visit.documentation?.plan ?? '';

    final summary = _SummaryLayout(
      sections: [
        _SummarySectionData(
          phase: EncounterPhase.subjective,
          title: EncounterPhase.subjective.label,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryField(
                label: 'Complaint',
                value: complaint,
                richDelta: _richDelta(docState, ClinicalNoteSection.complaint),
              ),
              _SummaryField(
                label: 'History',
                value: history,
                richDelta: _richDelta(docState, ClinicalNoteSection.history),
              ),
              _SummaryHealthProfile(patientId: effectiveVisit.patientId, visitId: visitId, docState: docState),
            ],
          ),
        ),
        _SummarySectionData(
          phase: EncounterPhase.objective,
          title: EncounterPhase.objective.label,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryField(
                label: 'Examination',
                value: examination,
                richDelta: _richDelta(docState, ClinicalNoteSection.examination),
              ),
              _SummaryField(
                label: 'Diagnosis',
                value: diagnosis,
                richDelta: _richDelta(docState, ClinicalNoteSection.diagnosis),
              ),
              if (effectiveVisit.pendingInvestigations.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.sm),
                InvestigationResultCaptureList(
                  pendingInvestigations: effectiveVisit.pendingInvestigations,
                  canEdit: canEdit,
                  visitId: visitId,
                  deferPersistence: canEdit,
                  onChanged: onRefresh ?? () {},
                ),
              ],
              _SummaryLinesField(
                label: 'Vital signs',
                lines: _formatVitalSigns(effectiveVisit.vitalSigns),
                emptyKey: const Key('encounter_review_vitals_empty'),
              ),
            ],
          ),
        ),
        _SummarySectionData(
          phase: EncounterPhase.plan,
          title: EncounterPhase.plan.label,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryField(label: 'Plan', value: plan, richDelta: _richDelta(docState, ClinicalNoteSection.plan)),
              _SummaryLinesField(
                label: 'Treatment plans',
                lines: _formatTreatmentPlans(effectiveVisit.treatmentPlans),
                emptyKey: const Key('encounter_review_treatment_plans_empty'),
              ),
              _SummaryLinesField(
                label: 'Investigations',
                lines: _formatInvestigations(effectiveVisit.investigations),
                emptyKey: const Key('encounter_review_investigations_empty'),
              ),
              if (onRefresh != null)
                VisitAttachmentList(
                  visitId: visitId,
                  branchId: effectiveVisit.branchId,
                  attachments: effectiveVisit.attachments,
                  canUpload: false,
                  onChanged: onRefresh!,
                  sectionKind: VisitPanelKind.attachment,
                  sectionTitle: 'Attachments',
                  summaryMode: true,
                ),
            ],
          ),
        ),
      ],
      canEdit: canEdit,
      onEditPhase: onEditPhase,
    );

    return KeyedSubtree(
      key: const Key('encounter_review'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final expandBody =
              constraints.hasBoundedHeight && constraints.maxHeight.isFinite && constraints.maxHeight > 0;

          return EncounterFieldCard(
            title: EncounterPhase.review.label,
            titleIcon: EncounterPhase.review.icon,
            expandBody: expandBody,
            child: summary,
          );
        },
      ),
    );
  }

  static List<String> _formatVitalSigns(List<VisitVitalSign> vitalSigns) {
    return [
      for (final sign in vitalSigns)
        '${sign.name}: ${sign.value}${sign.unit != null && sign.unit!.isNotEmpty ? ' ${sign.unit}' : ''}',
    ];
  }

  static List<String> _formatTreatmentPlans(List<TreatmentPlanItem> treatmentPlans) {
    return [
      for (final plan in treatmentPlans)
        [
          plan.medicationName,
          ...TreatmentPlanDisplay.subtitleParts(plan),
          if (plan.notes != null && plan.notes!.isNotEmpty) plan.notes!,
        ].join(' · '),
    ];
  }

  static List<String> _formatInvestigations(List<VisitInvestigation> investigations) {
    return [
      for (final investigation in investigations)
        [
          investigation.name,
          if (investigation.note != null && investigation.note!.isNotEmpty) investigation.note!,
          if (investigation.hasResult) investigation.result!,
        ].join(' · '),
    ];
  }

  static List<String> _formatAllergies(List<PatientAllergy> allergies) {
    return [
      for (final allergy in allergies)
        [
          allergy.substance,
          if (allergy.reaction != null && allergy.reaction!.isNotEmpty) allergy.reaction!,
        ].join(' · '),
    ];
  }

  static List<String> _formatChronicConditions(List<PatientChronicCondition> conditions) {
    return [
      for (final condition in conditions)
        [condition.name, if (condition.note != null && condition.note!.isNotEmpty) condition.note!].join(' · '),
    ];
  }

  static List<String> _formatCurrentMedications(List<PatientMedication> medications) {
    return [
      for (final medication in medications)
        [medication.name, if (medication.note != null && medication.note!.isNotEmpty) medication.note!].join(' · '),
    ];
  }
}

class _SummarySectionData {
  const _SummarySectionData({required this.phase, required this.title, required this.content});

  final EncounterPhase phase;
  final String title;
  final Widget content;
}

class _SummaryHealthProfile extends ConsumerWidget {
  const _SummaryHealthProfile({required this.patientId, required this.visitId, this.docState});

  final String patientId;
  final String visitId;
  final VisitDocumentationState? docState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (patientId.isEmpty) {
      return const SizedBox.shrink();
    }

    final safetyAsync = ref.watch(patientSafetyProvider(patientId));

    return safetyAsync.when(
      loading: () => const _SummaryLoadingField(message: 'Loading health profile…'),
      error: (error, stackTrace) => const _SummaryHealthProfileFields(
        allergies: [],
        chronicConditions: [],
        currentMedications: [],
        loadFailed: true,
      ),
      data: (safetyContext) {
        final effectiveSafety = docState?.effectivePatientSafety(safetyContext) ?? safetyContext;
        return _SummaryHealthProfileFields(
          allergies: effectiveSafety.allergies,
          chronicConditions: effectiveSafety.chronicConditions,
          currentMedications: effectiveSafety.currentMedications,
        );
      },
    );
  }
}

class _SummaryHealthProfileFields extends StatelessWidget {
  const _SummaryHealthProfileFields({
    required this.allergies,
    required this.chronicConditions,
    required this.currentMedications,
    this.loadFailed = false,
  });

  final List<PatientAllergy> allergies;
  final List<PatientChronicCondition> chronicConditions;
  final List<PatientMedication> currentMedications;
  final bool loadFailed;

  @override
  Widget build(BuildContext context) {
    if (loadFailed) {
      return _SummaryLinesField(
        label: 'Health profile',
        lines: const [],
        emptyKey: const Key('encounter_review_health_profile_error'),
        emptyMessage: 'Unable to load health profile.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryLinesField(
          label: 'Chronic conditions',
          lines: EncounterReview._formatChronicConditions(chronicConditions),
          emptyKey: const Key('encounter_review_chronic_conditions_empty'),
        ),
        _SummaryLinesField(
          label: 'Current medications',
          lines: EncounterReview._formatCurrentMedications(currentMedications),
          emptyKey: const Key('encounter_review_medications_empty'),
        ),
        _SummaryLinesField(
          label: 'Allergies',
          lines: EncounterReview._formatAllergies(allergies),
          emptyKey: const Key('encounter_review_allergies_empty'),
        ),
      ],
    );
  }
}

class _SummaryLoadingField extends StatelessWidget {
  const _SummaryLoadingField({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Text(message, style: theme.body(color: theme.mutedInk)),
    );
  }
}

class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({required this.sections, required this.canEdit, required this.onEditPhase});

  final List<_SummarySectionData> sections;
  final bool canEdit;
  final ValueChanged<EncounterPhase>? onEditPhase;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;
    final titleWidth = VisitPageTokens.summaryTitleWidth;
    const dividerInset = SpacingTokens.lg;

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite && constraints.maxHeight > 0;

        final sectionColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < sections.length; index++) ...[
              if (index > 0) ...[
                SizedBox(height: boundedHeight ? SpacingTokens.lg : VisitPageTokens.sectionGap),
                Divider(height: 1, color: theme.hairlineSoft),
                SizedBox(height: boundedHeight ? SpacingTokens.lg : VisitPageTokens.sectionGap),
              ],
              _SummarySectionRow(
                title: sections[index].title,
                phase: sections[index].phase,
                titleWidth: titleWidth,
                dividerInset: dividerInset,
                canEdit: canEdit,
                onEdit: onEditPhase == null ? null : () => onEditPhase!(sections[index].phase),
                content: sections[index].content,
              ),
            ],
          ],
        );

        final stack = Stack(
          clipBehavior: Clip.none,
          children: [
            if (boundedHeight) SingleChildScrollView(child: sectionColumn) else sectionColumn,
            Positioned(
              left: titleWidth,
              top: 0,
              bottom: 0,
              child: SizedBox(width: 1, child: VerticalDivider(width: 1, thickness: 1, color: theme.hairline)),
            ),
          ],
        );

        if (boundedHeight) {
          return SizedBox(height: constraints.maxHeight, width: double.infinity, child: stack);
        }

        return stack;
      },
    );
  }
}

class _SummarySectionRow extends StatelessWidget {
  const _SummarySectionRow({
    required this.title,
    required this.phase,
    required this.titleWidth,
    required this.dividerInset,
    required this.content,
    required this.canEdit,
    this.onEdit,
  });

  final String title;
  final EncounterPhase phase;
  final double titleWidth;
  final double dividerInset;
  final Widget content;
  final bool canEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: titleWidth,
          child: Padding(
            padding: EdgeInsets.only(right: dividerInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.title(size: 15)),
                if (canEdit && onEdit != null) ...[
                  const SizedBox(height: SpacingTokens.xs),
                  AppButton(
                    key: Key('encounter_review_edit_${phase.name}'),
                    label: 'Edit',
                    variant: AppButtonVariant.ghost,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    onPressed: onEdit,
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: dividerInset),
            child: content,
          ),
        ),
      ],
    );
  }
}

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value, this.richDelta});

  final String label;
  final String value;
  final List<dynamic>? richDelta;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
          const SizedBox(height: SpacingTokens.xs + 1),
          EncounterDetailText(value: value, richDelta: richDelta),
        ],
      ),
    );
  }
}

class _SummaryLinesField extends StatelessWidget {
  const _SummaryLinesField({required this.label, required this.lines, required this.emptyKey, this.emptyMessage = '—'});

  final String label;
  final List<String> lines;
  final Key emptyKey;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: theme.eyebrow(size: 10).copyWith(letterSpacing: 1.2)),
          const SizedBox(height: SpacingTokens.xs + 1),
          if (lines.isEmpty)
            KeyedSubtree(
              key: emptyKey,
              child: Text(emptyMessage, style: theme.body(color: theme.mutedInk)),
            )
          else if (lines.length == 1)
            Text(lines.first, style: theme.body())
          else
            for (var index = 0; index < lines.length; index++)
              _SummaryBulletItem(
                key: Key('encounter_review_${label.toLowerCase().replaceAll(' ', '_')}_item_$index'),
                text: lines[index],
                isLast: index == lines.length - 1,
              ),
        ],
      ),
    );
  }
}

/// One row in a multi-item summary list (non-rich-text list-builder fields).
class _SummaryBulletItem extends StatelessWidget {
  const _SummaryBulletItem({required this.text, required this.isLast, super.key});

  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : SpacingTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•', style: theme.body(color: theme.mutedInk)),
          const SizedBox(width: SpacingTokens.xs),
          Expanded(child: Text(text, style: theme.body())),
        ],
      ),
    );
  }
}
