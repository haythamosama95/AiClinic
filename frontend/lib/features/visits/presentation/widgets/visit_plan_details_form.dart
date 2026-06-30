import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_plan_details.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Structured plan outputs editor (014 US7).
class VisitPlanDetailsForm extends ConsumerStatefulWidget {
  const VisitPlanDetailsForm({required this.visitId, required this.state, required this.canEdit, super.key});

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;

  @override
  ConsumerState<VisitPlanDetailsForm> createState() => _VisitPlanDetailsFormState();
}

class _VisitPlanDetailsFormState extends ConsumerState<VisitPlanDetailsForm> {
  late final TextEditingController _followUpIntervalController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _referralController;
  late final TextEditingController _certificateReasonController;
  late final TextEditingController _followUpDateController;
  late final TextEditingController _certStartController;
  late final TextEditingController _certEndController;

  @override
  void initState() {
    super.initState();
    _followUpIntervalController = TextEditingController(text: widget.state.followUpInterval);
    _instructionsController = TextEditingController(text: widget.state.patientInstructions);
    _referralController = TextEditingController(text: widget.state.referral);
    _certificateReasonController = TextEditingController(text: widget.state.certificateReason);
    _followUpDateController = TextEditingController();
    _certStartController = TextEditingController();
    _certEndController = TextEditingController();
    _syncDateControllers();
  }

  @override
  void didUpdateWidget(covariant VisitPlanDetailsForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.followUpInterval != widget.state.followUpInterval) {
      _followUpIntervalController.text = widget.state.followUpInterval;
    }
    if (oldWidget.state.patientInstructions != widget.state.patientInstructions) {
      _instructionsController.text = widget.state.patientInstructions;
    }
    if (oldWidget.state.referral != widget.state.referral) {
      _referralController.text = widget.state.referral;
    }
    if (oldWidget.state.certificateReason != widget.state.certificateReason) {
      _certificateReasonController.text = widget.state.certificateReason;
    }
    if (oldWidget.state.followUpDate != widget.state.followUpDate ||
        oldWidget.state.certificateStartDate != widget.state.certificateStartDate ||
        oldWidget.state.certificateEndDate != widget.state.certificateEndDate) {
      _syncDateControllers();
    }
  }

  void _syncDateControllers() {
    _followUpDateController.text = _formatDate(widget.state.followUpDate);
    _certStartController.text = _formatDate(widget.state.certificateStartDate);
    _certEndController.text = _formatDate(widget.state.certificateEndDate);
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    return MaterialLocalizations.of(context).formatMediumDate(value);
  }

  @override
  void dispose() {
    _followUpIntervalController.dispose();
    _instructionsController.dispose();
    _referralController.dispose();
    _certificateReasonController.dispose();
    _followUpDateController.dispose();
    _certStartController.dispose();
    _certEndController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(visitDocumentationProvider(widget.visitId).notifier);
    final saveStatus = widget.state.planDetailsSaveStatus;
    final isSaving = saveStatus == PlanDetailsSaveStatus.saving;
    final enabled = widget.canEdit && !isSaving;

    return VisitSectionCard(
      kind: VisitPanelKind.clinicalNote,
      title: 'Structured plan outputs',
      description: 'Follow-up, instructions, referral, and certificate data (no document generation)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saveStatus == PlanDetailsSaveStatus.stale && widget.state.planDetailsErrorMessage != null) ...[
            AppAlert(title: widget.state.planDetailsErrorMessage!, variant: AppAlertVariant.destructive),
            const SizedBox(height: SpacingTokens.sm),
          ] else if (widget.state.planDetailsErrorMessage != null) ...[
            Text(
              widget.state.planDetailsErrorMessage!,
              style: context.visitTheme.caption(color: context.visitTheme.danger),
            ),
            const SizedBox(height: SpacingTokens.sm),
          ],
          AppTextField(
            label: 'Follow-up interval',
            hintText: 'e.g. in 2 weeks',
            controller: _followUpIntervalController,
            enabled: enabled,
            onChanged: notifier.updateFollowUpInterval,
          ),
          const SizedBox(height: SpacingTokens.sm),
          _DatePickerField(
            label: 'Follow-up date',
            controller: _followUpDateController,
            enabled: enabled,
            onPick: notifier.updateFollowUpDate,
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppTextField(
            label: 'Patient instructions',
            controller: _instructionsController,
            enabled: enabled,
            maxLines: 4,
            onChanged: notifier.updatePatientInstructions,
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppTextField(
            label: 'Referral',
            controller: _referralController,
            enabled: enabled,
            maxLines: 3,
            onChanged: notifier.updateReferral,
          ),
          const SizedBox(height: SpacingTokens.sm),
          Text('Medical certificate (data only)', style: context.visitTheme.eyebrow(size: 10)),
          const SizedBox(height: SpacingTokens.sm),
          Row(
            children: [
              Expanded(
                child: _DatePickerField(
                  label: 'Start date',
                  controller: _certStartController,
                  enabled: enabled,
                  onPick: notifier.updateCertificateStartDate,
                ),
              ),
              const SizedBox(width: SpacingTokens.sm),
              Expanded(
                child: _DatePickerField(
                  label: 'End date',
                  controller: _certEndController,
                  enabled: enabled,
                  onPick: notifier.updateCertificateEndDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          AppTextField(
            label: 'Certificate reason',
            controller: _certificateReasonController,
            enabled: enabled,
            maxLines: 3,
            onChanged: notifier.updateCertificateReason,
          ),
          if (widget.canEdit) ...[
            const SizedBox(height: SpacingTokens.md),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: const Key('visit_plan_details_save_button'),
                label: saveStatus == PlanDetailsSaveStatus.saved ? 'Saved' : 'Save plan details',
                icon: saveStatus == PlanDetailsSaveStatus.saved
                    ? const Icon(Icons.check, size: 18)
                    : const Icon(Icons.save_outlined, size: 18),
                isLoading: isSaving,
                onPressed: isSaving ? null : notifier.savePlanDetails,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.label, required this.controller, required this.enabled, required this.onPick});

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<DateTime?> onPick;

  Future<void> _pick(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      final utc = DateTime.utc(picked.year, picked.month, picked.day);
      onPick(utc);
      if (context.mounted) {
        controller.text = MaterialLocalizations.of(context).formatMediumDate(utc);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      enabled: enabled,
      suffixIcon: IconButton(
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        onPressed: enabled ? () => _pick(context) : null,
      ),
    );
  }
}

/// Read-only structured plan outputs summary.
class VisitPlanDetailsSummary extends StatelessWidget {
  const VisitPlanDetailsSummary({this.planDetails, super.key});

  final VisitPlanDetails? planDetails;

  @override
  Widget build(BuildContext context) {
    if (planDetails == null || planDetails!.isEmpty) {
      return const SizedBox.shrink();
    }

    final details = planDetails!;
    final theme = context.visitTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('STRUCTURED PLAN OUTPUTS', style: theme.eyebrow(size: 10)),
        const SizedBox(height: SpacingTokens.xs),
        if (details.followUpInterval != null && details.followUpInterval!.trim().isNotEmpty)
          _SummaryRow(label: 'Follow-up', value: details.followUpInterval!),
        if (details.followUpDate != null)
          _SummaryRow(
            label: 'Follow-up date',
            value: MaterialLocalizations.of(context).formatMediumDate(details.followUpDate!),
          ),
        if (details.patientInstructions != null && details.patientInstructions!.trim().isNotEmpty)
          _SummaryRow(label: 'Instructions', value: details.patientInstructions!),
        if (details.referral != null && details.referral!.trim().isNotEmpty)
          _SummaryRow(label: 'Referral', value: details.referral!),
        if (details.certificateStartDate != null ||
            details.certificateEndDate != null ||
            (details.certificateReason?.trim().isNotEmpty ?? false)) ...[
          const SizedBox(height: SpacingTokens.xs),
          Text('Certificate', style: theme.bodyStrong(size: 13)),
          if (details.certificateStartDate != null)
            _SummaryRow(
              label: 'Start',
              value: MaterialLocalizations.of(context).formatMediumDate(details.certificateStartDate!),
            ),
          if (details.certificateEndDate != null)
            _SummaryRow(
              label: 'End',
              value: MaterialLocalizations.of(context).formatMediumDate(details.certificateEndDate!),
            ),
          if (details.certificateReason != null && details.certificateReason!.trim().isNotEmpty)
            _SummaryRow(label: 'Reason', value: details.certificateReason!),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: context.visitTheme.eyebrow(size: 9)),
          Text(value, style: context.visitTheme.body()),
        ],
      ),
    );
  }
}
