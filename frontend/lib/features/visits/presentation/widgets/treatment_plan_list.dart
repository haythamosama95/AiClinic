import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';

/// Editable treatment plan list for visit documentation (V1-5 US4).
class TreatmentPlanList extends ConsumerStatefulWidget {
  const TreatmentPlanList({
    required this.visitId,
    required this.treatmentPlans,
    required this.canEdit,
    required this.onChanged,
    super.key,
  });

  final String visitId;
  final List<TreatmentPlanItem> treatmentPlans;
  final bool canEdit;
  final VoidCallback onChanged;

  @override
  ConsumerState<TreatmentPlanList> createState() => _TreatmentPlanListState();
}

class _TreatmentPlanListState extends ConsumerState<TreatmentPlanList> {
  bool _showAddForm = false;
  String? _editingPlanId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final plans = widget.treatmentPlans;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.canEdit && !_showAddForm)
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              key: const Key('treatment_plan_add_button'),
              label: 'Add medication',
              variant: AppButtonVariant.outline,
              icon: const Icon(Icons.add, size: 18),
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() {
                      _showAddForm = true;
                      _editingPlanId = null;
                    }),
            ),
          ),
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('treatment_plan_error'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive),
          ),
        ],
        if (plans.isEmpty && !_showAddForm)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
            child: Text(
              'No treatment plans added yet.',
              key: const Key('treatment_plan_empty'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
            ),
          ),
        ...plans.map(
          (plan) => Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: _editingPlanId == plan.id
                ? TreatmentPlanFormView(
                    key: Key('treatment_plan_edit_form_${plan.id}'),
                    initialPlan: plan,
                    isSubmitting: _isSubmitting,
                    onSubmit: (data) => _updatePlan(plan, data),
                    onCancel: () => setState(() => _editingPlanId = null),
                  )
                : TreatmentPlanCardView(
                    plan: plan,
                    canEdit: widget.canEdit,
                    onEdit: () => setState(() {
                      _editingPlanId = plan.id;
                      _showAddForm = false;
                    }),
                    onArchive: () => _archivePlan(plan),
                  ),
          ),
        ),
        if (_showAddForm)
          Padding(
            padding: const EdgeInsets.only(top: SpacingTokens.sm),
            child: TreatmentPlanFormView(
              key: const Key('treatment_plan_add_form'),
              isSubmitting: _isSubmitting,
              onSubmit: _addPlan,
              onCancel: () => setState(() => _showAddForm = false),
            ),
          ),
      ],
    );
  }

  Future<void> _addPlan(TreatmentPlanFormData data) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(visitRepositoryProvider).createTreatmentPlan(
            visitId: widget.visitId,
            medicationName: data.medicationName,
            dosage: data.dosage,
            frequency: data.frequency,
            duration: data.duration,
            notes: data.notes,
          );
      if (mounted) {
        setState(() {
          _showAddForm = false;
          _isSubmitting = false;
        });
        widget.onChanged();
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _updatePlan(TreatmentPlanItem existing, TreatmentPlanFormData data) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final params = data.updateParamsFor(existing);
      final hasChanges = params.medicationName != null ||
          params.dosage != null ||
          params.frequency != null ||
          params.duration != null ||
          params.notes != null;
      if (hasChanges) {
        await ref.read(visitRepositoryProvider).updateTreatmentPlan(
              treatmentPlanId: existing.id,
              medicationName: params.medicationName,
              dosage: params.dosage,
              frequency: params.frequency,
              duration: params.duration,
              notes: params.notes,
            );
      }
      if (mounted) {
        setState(() {
          _editingPlanId = null;
          _isSubmitting = false;
        });
        widget.onChanged();
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _archivePlan(TreatmentPlanItem plan) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove treatment plan?'),
        content: Text('Remove "${plan.medicationName}" from this visit?'),
        actions: [
          AppButton(label: 'Cancel', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false)),
          AppButton(label: 'Remove', variant: AppButtonVariant.destructive, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(visitRepositoryProvider).archiveTreatmentPlan(treatmentPlanId: plan.id);
      if (mounted) {
        setState(() => _isSubmitting = false);
        widget.onChanged();
      }
    } on RpcFailure catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = visitMessageForRpc(e);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }
}
