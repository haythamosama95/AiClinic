import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_encounter_persistence.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_name_normalizer.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_field_card.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/health_profile_card_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/save_to_catalog_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';

/// Opens the add-treatment-plan dialog used by [TreatmentPlanList].
Future<void> showTreatmentPlanAddDialog({
  required BuildContext context,
  required String visitId,
  required VoidCallback onRefresh,
  bool deferPersistence = false,
}) {
  return AppDialog.show<void>(
    context: context,
    title: 'Add medication',
    bodyBuilder: (dialogContext) => _TreatmentPlanAddDialogBody(
      visitId: visitId,
      hostContext: context,
      deferPersistence: deferPersistence,
      onCancel: () => Navigator.of(dialogContext).pop(),
      onRefresh: onRefresh,
      onSaved: () {
        Navigator.of(dialogContext).pop();
        onRefresh();
      },
    ),
  );
}

/// Editable treatment plan list for visit documentation (013 US3).
class TreatmentPlanList extends ConsumerStatefulWidget {
  const TreatmentPlanList({
    required this.visitId,
    required this.treatmentPlans,
    required this.canEdit,
    required this.onChanged,
    required this.sectionTitle,
    required this.sectionKind,
    this.encounterShell = false,
    this.expandBody = false,
    this.deferPersistence = false,
    super.key,
  });

  final String visitId;
  final List<TreatmentPlanItem> treatmentPlans;
  final bool canEdit;
  final VoidCallback onChanged;
  final String sectionTitle;
  final VisitPanelKind sectionKind;
  final bool encounterShell;
  final bool expandBody;
  final bool deferPersistence;

  @override
  ConsumerState<TreatmentPlanList> createState() => _TreatmentPlanListState();
}

class _TreatmentPlanListState extends ConsumerState<TreatmentPlanList> {
  String? _editingPlanId;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _hasItems => widget.treatmentPlans.isNotEmpty;

  Future<void> _openAddDialog() async {
    if (_isSubmitting) return;

    await showTreatmentPlanAddDialog(
      context: context,
      visitId: widget.visitId,
      onRefresh: widget.onChanged,
      deferPersistence: widget.deferPersistence,
    );
  }

  List<Widget>? _shelfActions() {
    if (!widget.canEdit || widget.encounterShell || !_hasItems) return null;

    return [
      AppNotchedCardAction(
        providesOwnBackground: true,
        action: AppButton(
          key: const Key('treatment_plan_add_button'),
          label: 'Add medication',
          size: AppFieldSize.sm,
          icon: const Icon(Icons.add, size: 18),
          onPressed: _isSubmitting ? null : _openAddDialog,
        ),
      ),
    ];
  }

  Widget? _encounterHeaderTrailing() {
    if (!widget.encounterShell || !widget.canEdit || !_hasItems) return null;

    final theme = context.visitTheme;
    return AppIconButton(
      key: const Key('treatment_plan_add_button'),
      icon: Icon(Icons.add_rounded, size: HealthProfileCardTokens.addIconSize, color: theme.pulse),
      tooltip: 'Add medication',
      onPressed: _isSubmitting ? null : _openAddDialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = encounterExpandedSectionBody(
      expandBody: widget.expandBody,
      centerWhenEmpty: widget.encounterShell && _shouldCenterEmptyState(),
      child: _buildBody(),
    );

    if (widget.encounterShell) {
      return EncounterFieldCard(
        title: widget.sectionTitle,
        titleIcon: widget.sectionKind.icon,
        expandBody: widget.expandBody,
        headerTrailing: _encounterHeaderTrailing(),
        child: body,
      );
    }

    return VisitSectionCard(
      kind: widget.sectionKind,
      title: widget.sectionTitle,
      headerActions: _shelfActions(),
      child: body,
    );
  }

  bool _shouldCenterEmptyState() {
    return !_hasItems && _errorMessage == null;
  }

  Widget _buildEmptyState() {
    return VisitEmptyHint(
      key: const Key('treatment_plan_empty'),
      message: 'No treatment plans added yet.',
      icon: Icons.medication_outlined,
      actionLabel: widget.canEdit ? 'Add medication' : null,
      onAction: widget.canEdit ? _openAddDialog : null,
      actionKey: widget.canEdit ? const Key('treatment_plan_add_button') : null,
    );
  }

  Widget _buildBody() {
    final colors = context.semanticColors;
    final plans = widget.treatmentPlans;

    if (widget.encounterShell && widget.expandBody && _shouldCenterEmptyState()) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMessage != null) ...[
          const SizedBox(height: SpacingTokens.sm),
          Text(
            _errorMessage!,
            key: const Key('treatment_plan_error'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.destructive),
          ),
        ],
        if (plans.isEmpty) _buildEmptyState(),
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
                    onEdit: () => setState(() => _editingPlanId = plan.id),
                    onArchive: () => _archivePlan(plan),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _updatePlan(TreatmentPlanItem existing, TreatmentPlanFormData data) async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final normalizedName = CatalogNameNormalizer.normalize(data.medicationName);
      if (normalizedName.isEmpty) {
        throw RpcFailure(
          RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Medication name is required.'),
        );
      }

      final normalizedData = TreatmentPlanFormData(
        medicationName: normalizedName,
        medicationId: data.medicationId,
        dosage: data.dosage,
        frequency: data.frequency,
        duration: data.duration,
        notes: data.notes,
      );
      final updateParams = normalizedData.updateParamsFor(existing);

      final hasChanges =
          updateParams.medicationName != null ||
          updateParams.medicationId != null ||
          updateParams.dosage != null ||
          updateParams.frequency != null ||
          updateParams.duration != null ||
          updateParams.notes != null;

      if (hasChanges) {
        await visitEncounterPersistence(
          ref,
          visitId: widget.visitId,
          deferPersistence: widget.deferPersistence,
        ).updateTreatmentPlan(
          treatmentPlanId: existing.id,
          medicationName: updateParams.medicationName,
          medicationId: updateParams.medicationId,
          dosage: updateParams.dosage,
          frequency: updateParams.frequency,
          duration: updateParams.duration,
          notes: updateParams.notes,
        );
      }

      if (!mounted) return;

      final becameCustom = data.isCustomMedication && existing.medicationId != null;
      final wasCustom = existing.medicationId == null;
      final nameChanged = normalizedName != existing.medicationName;

      setState(() {
        _editingPlanId = null;
        _isSubmitting = false;
      });
      widget.onChanged();

      if (mounted && (becameCustom || (wasCustom && nameChanged))) {
        await _maybeSaveCustomToCatalog(normalizedName: normalizedName);
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
      await visitEncounterPersistence(
        ref,
        visitId: widget.visitId,
        deferPersistence: widget.deferPersistence,
      ).archiveTreatmentPlan(treatmentPlanId: plan.id);
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

  Future<void> _maybeSaveCustomToCatalog({required String normalizedName}) async {
    if (!mounted) return;

    final save = await SaveToCatalogDialog.show(context, normalizedName: normalizedName, itemTypeLabel: 'medication');
    if (save != true || !mounted) return;

    try {
      await ref.read(visitRepositoryProvider).createCatalogMedication(name: normalizedName);
      if (!mounted) return;
      AppToast.success(context, message: 'Saved "$normalizedName" to your medication catalog.');
    } on RpcFailure catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: visitMessageForRpc(e));
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, message: e.toString());
    }
  }
}

class _TreatmentPlanAddDialogBody extends ConsumerStatefulWidget {
  const _TreatmentPlanAddDialogBody({
    required this.visitId,
    required this.hostContext,
    required this.onCancel,
    required this.onRefresh,
    required this.onSaved,
    this.deferPersistence = false,
  });

  final String visitId;
  final BuildContext hostContext;
  final bool deferPersistence;
  final VoidCallback onCancel;
  final VoidCallback onRefresh;
  final VoidCallback onSaved;

  @override
  ConsumerState<_TreatmentPlanAddDialogBody> createState() => _TreatmentPlanAddDialogBodyState();
}

class _TreatmentPlanAddDialogBodyState extends ConsumerState<_TreatmentPlanAddDialogBody> {
  bool _isSubmitting = false;

  Future<void> _submit(TreatmentPlanFormData data) async {
    setState(() => _isSubmitting = true);

    try {
      final normalizedName = CatalogNameNormalizer.normalize(data.medicationName);
      if (normalizedName.isEmpty) {
        throw RpcFailure(
          RpcResult(success: false, errorCode: 'INVALID_INPUT', errorMessage: 'Medication name is required.'),
        );
      }

      final isCustom = data.isCustomMedication;
      await visitEncounterPersistence(
        ref,
        visitId: widget.visitId,
        deferPersistence: widget.deferPersistence,
      ).createTreatmentPlan(
        medicationName: normalizedName,
        medicationId: data.medicationId,
        dosage: data.dosage,
        frequency: data.frequency,
        duration: data.duration,
        notes: data.notes,
      );

      if (!mounted) return;

      if (isCustom) {
        await _maybeSaveCustomToCatalog(normalizedName: normalizedName);
      }

      widget.onSaved();
    } on RpcFailure catch (e) {
      if (mounted) AppToast.error(context, message: visitMessageForRpc(e));
    } catch (e) {
      if (mounted) AppToast.error(context, message: e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _maybeSaveCustomToCatalog({required String normalizedName}) async {
    final save = await SaveToCatalogDialog.show(
      widget.hostContext,
      normalizedName: normalizedName,
      itemTypeLabel: 'medication',
    );
    if (save != true || !widget.hostContext.mounted) return;

    try {
      await ref.read(visitRepositoryProvider).createCatalogMedication(name: normalizedName);
      if (!widget.hostContext.mounted) return;
      AppToast.success(widget.hostContext, message: 'Saved "$normalizedName" to your medication catalog.');
      widget.onRefresh();
    } on RpcFailure catch (e) {
      if (!widget.hostContext.mounted) return;
      AppToast.error(widget.hostContext, message: visitMessageForRpc(e));
    } catch (e) {
      if (!widget.hostContext.mounted) return;
      AppToast.error(widget.hostContext, message: e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return TreatmentPlanFormView(
      key: const Key('treatment_plan_add_form'),
      isSubmitting: _isSubmitting,
      inDialog: true,
      onSubmit: _submit,
      onCancel: widget.onCancel,
    );
  }
}
