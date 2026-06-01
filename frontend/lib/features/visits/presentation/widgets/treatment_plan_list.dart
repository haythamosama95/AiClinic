import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/visit_rpc_messages.dart';
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
    final theme = Theme.of(context);
    final plans = widget.treatmentPlans;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Treatment plans', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (widget.canEdit && !_showAddForm)
              TextButton.icon(
                key: const Key('treatment_plan_add_button'),
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() {
                        _showAddForm = true;
                        _editingPlanId = null;
                      }),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            key: const Key('treatment_plan_error'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        if (plans.isEmpty && !_showAddForm)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No treatment plans added yet.',
              key: const Key('treatment_plan_empty'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ...plans.map(
          (plan) => _editingPlanId == plan.id
              ? TreatmentPlanFormView(
                  key: Key('treatment_plan_edit_form_${plan.id}'),
                  initialPlan: plan,
                  isSubmitting: _isSubmitting,
                  onSubmit: (data) => _updatePlan(plan.id, data),
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
        if (_showAddForm)
          TreatmentPlanFormView(
            key: const Key('treatment_plan_add_form'),
            isSubmitting: _isSubmitting,
            onSubmit: _addPlan,
            onCancel: () => setState(() => _showAddForm = false),
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
      await ref
          .read(visitRepositoryProvider)
          .createTreatmentPlan(
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

  Future<void> _updatePlan(String planId, TreatmentPlanFormData data) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(visitRepositoryProvider)
          .updateTreatmentPlan(
            treatmentPlanId: planId,
            medicationName: data.medicationName,
            dosage: data.dosage,
            frequency: data.frequency,
            duration: data.duration,
            notes: data.notes,
          );
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove treatment plan?'),
        content: Text('Remove "${plan.medicationName}" from this visit?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

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
