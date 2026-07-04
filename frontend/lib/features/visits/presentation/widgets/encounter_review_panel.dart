import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_attachments_panel.dart';

/// Read-only encounter summary with per-section edit links (014 US4 / FR-018).
class EncounterReviewPanel extends ConsumerWidget {
  const EncounterReviewPanel({
    required this.visitId,
    required this.visit,
    this.state,
    required this.canEdit,
    required this.canUploadAttachments,
    this.onEditPhase,
    super.key,
  });

  final String visitId;
  final VisitDetail visit;
  final VisitDocumentationState? state;
  final bool canEdit;
  final bool canUploadAttachments;
  final ValueChanged<EncounterPhase>? onEditPhase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));
    final docState = docAsync.value ?? state;
    final effectiveVisit = docState?.effectiveVisit ?? visit;

    final complaint = docState?.complaint ?? visit.documentation?.complaint ?? '';
    final history = docState?.history ?? visit.documentation?.history ?? '';
    final examination = docState?.examination ?? visit.documentation?.examination ?? '';
    final diagnosis = docState?.diagnosis ?? visit.documentation?.diagnosis ?? '';
    final plan = docState?.plan ?? visit.documentation?.plan ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummarySection(
          phase: EncounterPhase.subjective,
          title: EncounterPhase.subjective.label,
          canEdit: canEdit,
          onEdit: onEditPhase,
          children: [
            _SummaryField(label: 'Complaint', value: complaint),
            _SummaryField(label: 'History', value: history),
            _SummaryHealthLines(patientId: effectiveVisit.patientId, docState: docState),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        _SummarySection(
          phase: EncounterPhase.objective,
          title: EncounterPhase.objective.label,
          canEdit: canEdit,
          onEdit: onEditPhase,
          children: [
            _SummaryField(label: 'Examination', value: examination),
            _SummaryField(label: 'Diagnosis', value: diagnosis),
            _SummaryLinesField(
              label: 'Vital signs',
              lines: _formatVitalSigns(effectiveVisit.vitalSigns),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s6),
        _SummarySection(
          phase: EncounterPhase.plan,
          title: EncounterPhase.plan.label,
          canEdit: canEdit,
          onEdit: onEditPhase,
          children: [
            _SummaryField(label: 'Plan', value: plan),
            _SummaryLinesField(
              label: 'Treatment plans',
              lines: _formatTreatmentPlans(effectiveVisit.treatmentPlans),
            ),
            _SummaryLinesField(
              label: 'Investigations',
              lines: _formatInvestigations(effectiveVisit.investigations),
            ),
            if (effectiveVisit.attachments.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s3),
              EncounterAttachmentsPanel(
                visitId: visitId,
                branchId: effectiveVisit.branchId,
                attachments: effectiveVisit.attachments,
                canUpload: false,
              ),
            ],
          ],
        ),
      ],
    );
  }

  static List<String> _formatVitalSigns(List<VisitVitalSign> vitalSigns) {
    return [
      for (final sign in vitalSigns)
        '${sign.name}: ${sign.value}${sign.unit != null && sign.unit!.isNotEmpty ? ' ${sign.unit}' : ''}',
    ];
  }

  static List<String> _formatTreatmentPlans(List<TreatmentPlanItem> plans) {
    return [
      for (final plan in plans)
        [
          plan.medicationName,
          if (plan.dosage != null && plan.dosage!.isNotEmpty) plan.dosage!,
          if (plan.frequency != null && plan.frequency!.isNotEmpty) plan.frequency!,
          if (plan.duration != null && plan.duration!.isNotEmpty) plan.duration!,
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
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.phase,
    required this.title,
    required this.canEdit,
    required this.children,
    this.onEdit,
  });

  final EncounterPhase phase;
  final String title;
  final bool canEdit;
  final List<Widget> children;
  final ValueChanged<EncounterPhase>? onEdit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: AppCardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: title,
            actions: canEdit && onEdit != null
                ? AppButton(
                    label: 'Edit',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    leadingIcon: LucideIcons.pencil,
                    onPressed: () => onEdit!(phase),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.s3),
          ...children,
        ],
      ),
    );
  }
}

class _SummaryField extends StatelessWidget {
  const _SummaryField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final display = value.trim().isEmpty ? '—' : value.trim();

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: typography.caption.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.s0_5),
          Text(display, style: typography.body.copyWith(color: colors.textPrimary)),
        ],
      ),
    );
  }
}

class _SummaryLinesField extends StatelessWidget {
  const _SummaryLinesField({required this.label, required this.lines});

  final String label;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: typography.caption.copyWith(color: colors.textTertiary)),
          const SizedBox(height: AppSpacing.s0_5),
          if (lines.isEmpty)
            Text('—', style: typography.body.copyWith(color: colors.textPrimary))
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s0_5),
                child: Text(line, style: typography.body.copyWith(color: colors.textPrimary)),
              ),
        ],
      ),
    );
  }
}

class _SummaryHealthLines extends ConsumerWidget {
  const _SummaryHealthLines({required this.patientId, this.docState});

  final String patientId;
  final VisitDocumentationState? docState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safetyAsync = ref.watch(patientSafetyProvider(patientId));

    return safetyAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (base) {
        final safety = docState?.effectivePatientSafety(base) ?? base;
        if (safety.allergies.isEmpty) return const SizedBox.shrink();
        return _SummaryLinesField(
          label: 'Allergies',
          lines: [
            for (final allergy in safety.allergies)
              allergy.reaction != null && allergy.reaction!.isNotEmpty
                  ? '${allergy.substance} · ${allergy.reaction}'
                  : allergy.substance,
          ],
        );
      },
    );
  }
}
