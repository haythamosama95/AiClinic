import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/patient_safety.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_options.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/patient_safety_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';

/// Read-only encounter summary ledger (web `VisitSummary`).
class VisitSummarySection extends ConsumerStatefulWidget {
  const VisitSummarySection({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<VisitSummarySection> createState() => _VisitSummarySectionState();
}

class _VisitSummarySectionState extends ConsumerState<VisitSummarySection> {
  var _finalizing = false;

  Future<void> _finalizeVisit() async {
    if (_finalizing) {
      return;
    }

    setState(() => _finalizing = true);
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);

    try {
      await notifier.completeVisit();
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(message: 'Visit finalized successfully.', variant: AppToastVariant.success),
      );
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      appToast(context, AppToastInput(message: visitMessageForRpc(error), variant: AppToastVariant.danger));
    } catch (_) {
      if (!mounted) {
        return;
      }
      appToast(
        context,
        const AppToastInput(
          message: 'Could not finalize the visit. Please try again.',
          variant: AppToastVariant.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _finalizing = false);
      }
    }
  }

  void _editVisit() {
    ref.read(encounterActivePhaseProvider(widget.visitId).notifier).setPhase(EncounterPhase.plan);
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(visitDocumentationProvider(widget.visitId));
    final docState = docAsync.value;
    if (docState == null) {
      return const AppSkeleton(variant: SkeletonVariant.rectangular, height: 320);
    }

    final colors = context.appColors;
    final elevation = context.appElevation;
    final patientId = docState.visit.patientId;
    final safetyAsync = ref.watch(patientSafetyProvider(patientId));
    final baseSafety = safetyAsync.value ?? const PatientSafetyContext();
    final safety = docState.effectivePatientSafety(baseSafety);
    final effectiveVisit = docState.effectiveVisit;
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final canSubmit = notifier.canSubmitVisit(docState.visit);
    final readiness = evaluateVisitSubmitReadiness(docState);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review visit', style: AppTypography.h2(context).copyWith(color: colors.textPrimary)),
        const SizedBox(height: AppSpacing.space1),
        Text(
          'Verify intake, findings, and treatment before finalizing this encounter.',
          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.space6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            border: Border.all(color: colors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.x2l),
            boxShadow: elevation.shadows1,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.x2l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _VisitSummaryLedgerSection(
                  title: 'Intake',
                  rows: [
                    _LedgerRow(
                      label: 'Complaint',
                      value: _LedgerText(value: docState.complaint),
                    ),
                    _LedgerRow(
                      label: 'History',
                      value: _LedgerText(value: docState.history),
                    ),
                    _LedgerRow(
                      label: 'Chronic conditions',
                      value: _LedgerInlineList(
                        items: [
                          for (final item in safety.chronicConditions)
                            _LedgerInlineItem(label: item.name, meta: item.note),
                        ],
                        emptyLabel: 'None recorded',
                      ),
                    ),
                    _LedgerRow(
                      label: 'Allergies',
                      value: _LedgerInlineList(
                        items: [
                          for (final item in safety.allergies)
                            _LedgerInlineItem(label: item.substance, meta: item.reaction),
                        ],
                        emptyLabel: 'None recorded',
                      ),
                    ),
                    _LedgerRow(
                      label: 'Current medications',
                      value: _LedgerInlineList(
                        items: [
                          for (final item in safety.currentMedications)
                            _LedgerInlineItem(label: item.name, meta: item.note, metaInParens: false),
                        ],
                        emptyLabel: 'None recorded',
                      ),
                    ),
                  ],
                ),
                _VisitSummaryLedgerSection(
                  title: 'Findings & diagnosis',
                  rows: [
                    _LedgerRow(
                      label: 'Examination',
                      value: _LedgerText(value: docState.examination),
                    ),
                    _LedgerRow(
                      label: 'Vital signs',
                      value: _LedgerVitalSigns(signs: effectiveVisit.vitalSigns),
                    ),
                    _LedgerRow(
                      label: 'Diagnosis',
                      value: _LedgerText(value: docState.diagnosis),
                    ),
                  ],
                ),
                _VisitSummaryLedgerSection(
                  title: 'Treatment',
                  isLast: true,
                  rows: [
                    _LedgerRow(
                      label: 'Treatment notes',
                      value: _LedgerText(value: docState.plan),
                    ),
                    _LedgerRow(
                      label: 'Investigations',
                      value: _LedgerInvestigations(investigations: effectiveVisit.investigations),
                    ),
                    _LedgerRow(
                      label: 'Treatment plan',
                      value: _LedgerTreatmentPlans(plans: effectiveVisit.treatmentPlans),
                    ),
                    _LedgerRow(
                      label: 'Attachments',
                      value: _LedgerAttachments(attachments: effectiveVisit.attachments),
                    ),
                  ],
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.borderSubtle)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 640;
                      final horizontalPadding = isWide ? AppSpacing.space6 : AppSpacing.space5;
                      final editButton = AppButton(
                        variant: AppButtonVariant.secondary,
                        leadingIcon: const Icon(Icons.arrow_back_rounded, size: 16),
                        onPressed: _editVisit,
                        child: const Text('Edit visit'),
                      );
                      final finalizeButton = AppButton(
                        trailingIcon: _finalizing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline_rounded, size: 16),
                        onPressed: canSubmit && readiness.hasMinimumDocumentation && !_finalizing
                            ? _finalizeVisit
                            : null,
                        child: const Text('Finalize visit'),
                      );

                      if (isWide) {
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            AppSpacing.space4,
                            horizontalPadding,
                            AppSpacing.space4,
                          ),
                          child: Row(children: [editButton, const Spacer(), finalizeButton]),
                        );
                      }

                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          AppSpacing.space4,
                          horizontalPadding,
                          AppSpacing.space4,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (canSubmit) finalizeButton,
                            if (canSubmit) const SizedBox(height: AppSpacing.space3),
                            editButton,
                          ],
                        ),
                      );
                    },
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

class _LedgerRow {
  const _LedgerRow({required this.label, required this.value});

  final String label;
  final Widget value;
}

class _LedgerInlineItem {
  const _LedgerInlineItem({required this.label, this.meta, this.metaInParens = true});

  final String label;
  final String? meta;
  final bool metaInParens;
}

class _VisitSummaryLedgerSection extends StatelessWidget {
  const _VisitSummaryLedgerSection({required this.title, required this.rows, this.isLast = false});

  final String title;
  final List<_LedgerRow> rows;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 640;
          final horizontalPadding = isWide ? AppSpacing.space6 : AppSpacing.space5;

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(horizontalPadding, AppSpacing.space3, horizontalPadding, 0),
                  child: Text(title, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    children: [
                      for (var index = 0; index < rows.length; index++)
                        _VisitSummaryLedgerEntry(
                          label: rows[index].label,
                          value: rows[index].value,
                          isLast: index == rows.length - 1,
                          labelFlex: 38,
                        ),
                    ],
                  ),
                ),
              ],
            );
          }

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 112,
                    padding: const EdgeInsets.only(
                      top: AppSpacing.space3,
                      bottom: AppSpacing.space3,
                      right: AppSpacing.space4,
                    ),
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: colors.borderSubtle)),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(title, style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.space5),
                      child: Column(
                        children: [
                          for (var index = 0; index < rows.length; index++)
                            _VisitSummaryLedgerEntry(
                              label: rows[index].label,
                              value: rows[index].value,
                              isLast: index == rows.length - 1,
                              wide: true,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VisitSummaryLedgerEntry extends StatelessWidget {
  const _VisitSummaryLedgerEntry({
    required this.label,
    required this.value,
    required this.isLast,
    this.wide = false,
    this.labelFlex = 38,
  });

  final String label;
  final Widget value;
  final bool isLast;
  final bool wide;
  final int labelFlex;

  TextStyle _labelStyle(BuildContext context) {
    return AppTypography.caption(context).copyWith(color: context.appColors.textTertiary);
  }

  TextStyle _valueStyle(BuildContext context) {
    return AppTypography.bodySm(context).copyWith(color: context.appColors.textPrimary);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final border = isLast ? null : Border(bottom: BorderSide(color: colors.borderSubtle));

    if (!wide) {
      return DecoratedBox(
        decoration: BoxDecoration(border: border),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                flex: labelFlex,
                child: Text(label, style: _labelStyle(context)),
              ),
              const SizedBox(width: AppSpacing.space4),
              Expanded(
                child: DefaultTextStyle(style: _valueStyle(context), child: value),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(border: border),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 168, child: Text(label, style: _labelStyle(context))),
            const SizedBox(width: AppSpacing.space5),
            Expanded(
              child: DefaultTextStyle(style: _valueStyle(context), child: value),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerText extends StatelessWidget {
  const _LedgerText({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (value.trim().isEmpty) {
      return Text('—', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary));
    }
    return Text(value, style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary));
  }
}

class _LedgerInlineList extends StatelessWidget {
  const _LedgerInlineList({required this.items, required this.emptyLabel});

  final List<_LedgerInlineItem> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (items.isEmpty) {
      return Text(emptyLabel, style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary));
    }

    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              TextSpan(
                text: ' · ',
                style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary),
              ),
            TextSpan(
              text: items[index].label,
              style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
            ),
            if (items[index].meta?.trim().isNotEmpty ?? false)
              TextSpan(
                text: items[index].metaInParens ? ' (${items[index].meta!.trim()})' : ' ${items[index].meta!.trim()}',
                style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }
}

class _LedgerVitalSigns extends StatelessWidget {
  const _LedgerVitalSigns({required this.signs});

  final List<VisitVitalSign> signs;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (signs.isEmpty) {
      return Text('None recorded', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < signs.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.space1),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: signs[index].name,
                  style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                ),
                TextSpan(
                  text: ' · ',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary),
                ),
                TextSpan(
                  text: _formatVitalValue(signs[index]),
                  style: AppTypography.bodySm(context).copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _formatVitalValue(VisitVitalSign sign) {
    final value = sign.value.trim().isEmpty ? '—' : sign.value.trim();
    final unit = sign.unit?.trim();
    if (unit != null && unit.isNotEmpty) {
      return '$value $unit';
    }
    return value;
  }
}

class _LedgerInvestigations extends StatelessWidget {
  const _LedgerInvestigations({required this.investigations});

  final List<VisitInvestigation> investigations;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (investigations.isEmpty) {
      return Text('None ordered', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < investigations.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.space1),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: investigations[index].name,
                  style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500),
                ),
                if (investigations[index].note?.trim().isNotEmpty ?? false)
                  TextSpan(
                    text: ' — ${investigations[index].note!.trim()}',
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LedgerTreatmentPlans extends StatelessWidget {
  const _LedgerTreatmentPlans({required this.plans});

  final List<TreatmentPlanItem> plans;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (plans.isEmpty) {
      return Text('None prescribed', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < plans.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.space1),
          Builder(
            builder: (context) {
              final details = _formatPlanDetails(plans[index]);
              final name = plans[index].medicationName.trim().isEmpty ? 'Unspecified' : plans[index].medicationName;
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: name,
                      style: AppTypography.bodySm(
                        context,
                      ).copyWith(color: colors.textPrimary, fontWeight: FontWeight.w500),
                    ),
                    if (details.isNotEmpty)
                      TextSpan(
                        text: ' — $details',
                        style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  static String _formatPlanDetails(TreatmentPlanItem plan) {
    return [
      plan.dosage,
      treatmentFrequencyLabel(plan.frequency),
      treatmentDurationLabel(plan.duration),
    ].where((part) => part != null && part.trim().isNotEmpty && part != '—').join(' · ');
  }
}

class _LedgerAttachments extends StatelessWidget {
  const _LedgerAttachments({required this.attachments});

  final List<VisitAttachmentItem> attachments;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (attachments.isEmpty) {
      return Text('No attachments', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < attachments.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.space1),
          Row(
            children: [
              Icon(Icons.description_outlined, size: 14, color: colors.iconMuted),
              const SizedBox(width: AppSpacing.space2),
              Expanded(
                child: Text(
                  attachments[index].label ?? attachments[index].id,
                  style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
