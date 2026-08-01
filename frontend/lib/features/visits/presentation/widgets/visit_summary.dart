import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_catalog_options.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stagger.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_summary_ledger.dart';

/// Review summary with warning band, ledger sections, and finalize actions (web `VisitSummary`).
class VisitSummary extends ConsumerStatefulWidget {
  const VisitSummary({
    required this.visitId,
    required this.onEdit,
    required this.onFinalize,
    this.finalizing = false,
    super.key,
  });

  final String visitId;
  final VoidCallback onEdit;
  final VoidCallback onFinalize;
  final bool finalizing;

  @override
  ConsumerState<VisitSummary> createState() => _VisitSummaryState();
}

class _VisitSummaryState extends ConsumerState<VisitSummary> with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final CurvedAnimation _fadeAnimation;
  var _fadeConfigured = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this);
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: AppMotionEasing.out);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fadeConfigured) {
      return;
    }
    _fadeConfigured = true;

    final reducedMotion = AppMotion.prefersReducedMotion(context);
    _fadeController.duration = AppMotion.resolveDuration(
      AppMotionPreset.fadeScale,
      reducedMotion: reducedMotion,
    );

    if (reducedMotion) {
      _fadeController.value = 1;
      return;
    }

    _fadeController.forward(from: 0);
  }

  @override
  void dispose() {
    _fadeAnimation.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));

    return docAsync.when(
      loading: () => const AppSkeletonizerZone(
        child: AppSkeleton(variant: SkeletonVariant.rectangular, height: 320),
      ),
      error: (error, _) => AppErrorState(message: error.toString()),
      data: (state) {
        final patientId = state.visit.patientId;
        final safetyAsync = ref.watch(patientSafetyProvider(patientId));
        final safety = safetyAsync.maybeWhen(
          data: (base) => state.effectivePatientSafety(base),
          orElse: () => const PatientSafetyContext(),
        );

        final visit = state.effectiveVisit;
        final readiness = evaluateVisitSubmitReadiness(state);
        final canFinalize = readiness.hasMinimumDocumentation && !widget.finalizing;
        final isSaving = state.saveStatus == DocumentationSaveStatus.saving || widget.finalizing;

        final intakeRows = _buildIntakeRows(state, safety);
        final findingsRows = _buildFindingsRows(state, visit.vitalSigns);
        final treatmentRows = _buildTreatmentRows(
          state,
          visit.investigations,
          visit.treatmentPlans,
          visit.attachments,
        );

        final card = AppCard(
          variant: CardVariant.raised,
          padding: CardPadding.sm,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _WarningBand(),
                VisitSummaryLedger(
                  title: 'Intake',
                  rows: intakeRows,
                  vsync: this,
                  delay: const Duration(milliseconds: 50),
                ),
                VisitSummaryLedger(
                  title: 'Findings & diagnosis',
                  rows: findingsRows,
                  vsync: this,
                  delay: const Duration(milliseconds: 100),
                ),
                VisitSummaryLedger(
                  title: 'Treatment',
                  rows: treatmentRows,
                  vsync: this,
                  delay: const Duration(milliseconds: 150),
                  isLast: true,
                ),
                _SummaryFooter(
                  canFinalize: canFinalize,
                  isSaving: isSaving,
                  readiness: readiness,
                  onEdit: widget.onEdit,
                  onFinalize: canFinalize ? widget.onFinalize : null,
                ),
              ],
            ),
          ),
        );

        final reducedMotion = AppMotion.prefersReducedMotion(context);
        final animatedCard = reducedMotion
            ? card
            : AppMotion.animatedPreset(
                context: context,
                preset: AppMotionPreset.fadeScale,
                animation: _fadeAnimation,
                child: card,
              );

        return VisitStagger(
          vsync: this,
          stepMs: 60,
          children: [VisitStaggeredItem(child: animatedCard)],
        );
      },
    );
  }

  List<LedgerRow> _buildIntakeRows(VisitDocumentationState state, PatientSafetyContext safety) {
    return [
      LedgerRow(label: 'Complaint', value: LedgerText(value: state.complaint)),
      LedgerRow(label: 'History', value: LedgerText(value: state.history)),
      LedgerRow(
        label: 'Chronic conditions',
        value: LedgerInlineList(
          items: [
            for (final condition in safety.chronicConditions)
              LedgerInlineItem(
                id: condition.id,
                label: condition.name,
                meta: condition.note,
              ),
          ],
          emptyLabel: 'None recorded',
        ),
      ),
      LedgerRow(
        label: 'Allergies',
        value: LedgerInlineList(
          items: [
            for (final allergy in safety.allergies)
              LedgerInlineItem(
                id: allergy.id,
                label: allergy.substance,
                meta: allergy.reaction,
              ),
          ],
          emptyLabel: 'None recorded',
        ),
      ),
      LedgerRow(
        label: 'Current medications',
        value: LedgerInlineList(
          items: [
            for (final medication in safety.currentMedications)
              LedgerInlineItem(
                id: medication.id,
                label: medication.name,
                meta: medication.note,
              ),
          ],
          emptyLabel: 'None recorded',
        ),
      ),
    ];
  }

  List<LedgerRow> _buildFindingsRows(VisitDocumentationState state, List<VisitVitalSign> vitalSigns) {
    return [
      LedgerRow(label: 'Examination', value: LedgerText(value: state.examination)),
      LedgerRow(
        label: 'Vital signs',
        value: vitalSigns.isEmpty
            ? Text('None recorded', style: TextStyle(color: context.appColors.textTertiary))
            : _VitalSignsList(vitalSigns: vitalSigns),
      ),
      LedgerRow(label: 'Diagnosis', value: LedgerText(value: state.diagnosis)),
    ];
  }

  List<LedgerRow> _buildTreatmentRows(
    VisitDocumentationState state,
    List<VisitInvestigation> investigations,
    List<TreatmentPlanItem> treatmentPlans,
    List<VisitAttachmentItem> attachments,
  ) {
    return [
      LedgerRow(label: 'Treatment notes', value: LedgerText(value: state.plan)),
      LedgerRow(
        label: 'Investigations',
        value: investigations.isEmpty
            ? Text('None ordered', style: TextStyle(color: context.appColors.textTertiary))
            : _InvestigationsList(investigations: investigations),
      ),
      LedgerRow(
        label: 'Treatment plan',
        value: treatmentPlans.isEmpty
            ? Text('None prescribed', style: TextStyle(color: context.appColors.textTertiary))
            : _TreatmentPlanList(plans: treatmentPlans),
      ),
      LedgerRow(
        label: 'Attachments',
        value: attachments.isEmpty
            ? Text('No attachments', style: TextStyle(color: context.appColors.textTertiary))
            : _AttachmentsList(attachments: attachments),
      ),
    ];
  }
}

class _WarningBand extends StatelessWidget {
  const _WarningBand();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusWarningSurface,
        border: Border(bottom: BorderSide(color: colors.statusWarningBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.space5,
          AppSpacing.space4,
          AppSpacing.space5,
          AppSpacing.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pending review',
              style: AppTypography.overline(context).copyWith(color: colors.statusWarningFg),
            ),
            const SizedBox(height: AppSpacing.space1),
            Text(
              'Verify intake, findings, and treatment before finalizing this encounter.',
              style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryFooter extends StatelessWidget {
  const _SummaryFooter({
    required this.canFinalize,
    required this.isSaving,
    required this.readiness,
    required this.onEdit,
    required this.onFinalize,
  });

  final bool canFinalize;
  final bool isSaving;
  final VisitSubmitReadiness readiness;
  final VoidCallback onEdit;
  final VoidCallback? onFinalize;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final finalizeButton = AppButton(
      variant: AppButtonVariant.primary,
      loading: isSaving,
      disabled: !canFinalize,
      trailingIcon: const Icon(Icons.check_circle_outline_rounded, size: 16),
      onPressed: onFinalize,
      child: const Text('Finalize visit'),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 640;

            final editButton = Material(
              type: MaterialType.transparency,
              child: AppButton(
                variant: AppButtonVariant.secondary,
                leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
                onPressed: onEdit,
                child: const Text('Edit visit'),
              ),
            );

            final finalize = canFinalize
                ? Material(type: MaterialType.transparency, child: finalizeButton)
                : AppTooltip(
                    message: _finalizeDisabledMessage(readiness),
                    child: Material(type: MaterialType.transparency, child: finalizeButton),
                  );

            if (!isWide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  finalize,
                  const SizedBox(height: AppSpacing.space3),
                  editButton,
                ],
              );
            }

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [editButton, finalize],
            );
          },
        ),
      ),
    );
  }

  String _finalizeDisabledMessage(VisitSubmitReadiness readiness) {
    if (!readiness.hasMinimumDocumentation) {
      return 'Add clinical documentation before finalizing this visit.';
    }
    return 'Unable to finalize this visit.';
  }
}

class _VitalSignsList extends StatelessWidget {
  const _VitalSignsList({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final vital in vitalSigns)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space1),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: vital.name,
                    style: TextStyle(color: colors.textSecondary),
                  ),
                  TextSpan(
                    text: ' · ',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                  TextSpan(
                    text: '${vital.value.isEmpty ? '—' : vital.value}${vital.unit != null && vital.unit!.isNotEmpty ? ' ${vital.unit}' : ''}',
                    style: AppTypography.body(context).copyWith(
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InvestigationsList extends StatelessWidget {
  const _InvestigationsList({required this.investigations});

  final List<VisitInvestigation> investigations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final investigation in investigations)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: investigation.name,
                    style: AppTypography.body(context).copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (investigation.note != null && investigation.note!.trim().isNotEmpty)
                    TextSpan(
                      text: ' — ${investigation.note}',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TreatmentPlanList extends StatelessWidget {
  const _TreatmentPlanList({required this.plans});

  final List<TreatmentPlanItem> plans;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: plan.medicationName.isNotEmpty ? plan.medicationName : 'Unspecified',
                    style: AppTypography.body(context).copyWith(fontWeight: FontWeight.w500),
                  ),
                  TextSpan(
                    text: ' — ${_formatPlanDetails(plan)}',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _formatPlanDetails(TreatmentPlanItem plan) {
    return [
      if (plan.dosage != null && plan.dosage!.trim().isNotEmpty) plan.dosage,
      if (plan.frequency != null && plan.frequency!.trim().isNotEmpty)
        getFrequencyLabel(plan.frequency!),
      if (plan.duration != null && plan.duration!.trim().isNotEmpty) getDurationLabel(plan.duration!),
    ].whereType<String>().join(' · ');
  }
}

class _AttachmentsList extends StatelessWidget {
  const _AttachmentsList({required this.attachments});

  final List<VisitAttachmentItem> attachments;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attachment in attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.space1),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 14, color: colors.iconMuted),
                const SizedBox(width: AppSpacing.space2),
                Expanded(child: Text(_attachmentDisplayName(attachment))),
              ],
            ),
          ),
      ],
    );
  }
}

String _attachmentDisplayName(VisitAttachmentItem attachment) {
  final label = attachment.label?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }
  return switch (attachment.fileType.name) {
    'pdf' => 'Document.pdf',
    'jpeg' => 'Image.jpg',
    'png' => 'Image.png',
    'docx' => 'Document.docx',
    _ => 'Attachment',
  };
}
