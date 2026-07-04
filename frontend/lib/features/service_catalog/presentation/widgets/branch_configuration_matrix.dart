import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/application/service_catalog_rpc_messages.dart';
import 'package:ai_clinic/features/service_catalog/application/service_form_validation.dart';
import 'package:ai_clinic/features/service_catalog/data/service_catalog_repository.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_config.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_form_draft_snapshot.dart';
import 'package:ai_clinic/features/service_catalog/presentation/providers/service_editor_notifier.dart';
import 'package:ai_clinic/features/service_catalog/presentation/utils/service_price_preview.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/copy_configuration_dialog.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/promotion_editor.dart';

/// Per-branch activation, override, promotion, and price preview matrix (015 US3–US4).
class BranchConfigurationMatrix extends ConsumerStatefulWidget {
  const BranchConfigurationMatrix({
    required this.defaultPriceWire,
    required this.canManage,
    required this.isCreateMode,
    required this.branches,
    required this.draftSnapshot,
    required this.pendingByBranchId,
    required this.onPendingChanged,
    this.serviceId,
    super.key,
  });

  final String? serviceId;
  final String defaultPriceWire;
  final bool canManage;
  final bool isCreateMode;
  final List<ServiceBranchConfig> branches;
  final ServiceFormDraftSnapshot draftSnapshot;
  final Map<String, PendingBranchConfiguration> pendingByBranchId;
  final ValueChanged<Map<String, PendingBranchConfiguration>> onPendingChanged;

  @override
  ConsumerState<BranchConfigurationMatrix> createState() => _BranchConfigurationMatrixState();
}

class _BranchConfigurationMatrixState extends ConsumerState<BranchConfigurationMatrix> {
  final Map<String, bool> _rowSubmitted = {};
  final Map<String, String?> _rowErrors = {};

  List<ServiceBranchConfig> get _visibleBranches {
    if (widget.isCreateMode) {
      final branchIds = widget.draftSnapshot.assignAllBranches
          ? widget.branches.map((row) => row.branchId).toSet()
          : widget.draftSnapshot.selectedBranchIds;
      return widget.branches.where((row) => branchIds.contains(row.branchId)).map((row) {
        final pending = widget.pendingByBranchId[row.branchId];
        if (pending == null) {
          return row;
        }
        return ServiceBranchConfig.fromPending(pending);
      }).toList(growable: false);
    }
    return widget.branches;
  }

  String _effectivePriceWire(ServiceBranchConfig row) {
    final override = row.priceOverride?.wireValue;
    if (override != null && override.isNotEmpty) {
      return override;
    }
    return widget.defaultPriceWire;
  }

  void _updatePending(String branchId, PendingBranchConfiguration pending) {
    final next = Map<String, PendingBranchConfiguration>.from(widget.pendingByBranchId);
    next[branchId] = pending;
    widget.onPendingChanged(next);
  }

  Future<void> _saveBranchSettings(ServiceBranchConfig row, {required bool active, String? priceOverride}) async {
    if (widget.isCreateMode) {
      _updatePending(
        row.branchId,
        (widget.pendingByBranchId[row.branchId] ?? PendingBranchConfiguration(branchId: row.branchId, branchName: row.branchName))
            .copyWith(active: active, priceOverride: priceOverride, clearPriceOverride: priceOverride == null),
      );
      return;
    }

    final serviceId = widget.serviceId;
    final updatedAt = row.updatedAt;
    if (serviceId == null || updatedAt == null) {
      return;
    }

    try {
      await ref.read(serviceEditorProvider(serviceId).notifier).configureServiceBranch(
            branchId: row.branchId,
            expectedUpdatedAt: updatedAt,
            active: active,
            priceOverride: priceOverride,
          );
      if (mounted) {
        setState(() => _rowErrors.remove(row.branchId));
      }
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _rowErrors[row.branchId] = serviceCatalogMessageForRpc(error));
    }
  }

  Future<void> _savePromotion(ServiceBranchConfig row, ServicePromotion promotion) async {
    if (widget.isCreateMode) {
      _updatePending(
        row.branchId,
        (widget.pendingByBranchId[row.branchId] ?? PendingBranchConfiguration(branchId: row.branchId, branchName: row.branchName))
            .copyWith(promotion: promotion),
      );
      return;
    }

    final serviceId = widget.serviceId;
    final updatedAt = row.updatedAt;
    if (serviceId == null || updatedAt == null) {
      return;
    }

    try {
      await ref.read(serviceEditorProvider(serviceId).notifier).setServicePromotion(
            branchId: row.branchId,
            expectedUpdatedAt: updatedAt,
            promotionPrice: promotion.wirePrice,
            startDate: promotion.startDate,
            endDate: promotion.endDate,
          );
      if (mounted) {
        setState(() => _rowErrors.remove(row.branchId));
      }
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _rowErrors[row.branchId] = serviceCatalogMessageForRpc(error));
    }
  }

  Future<void> _clearPromotion(ServiceBranchConfig row) async {
    if (widget.isCreateMode) {
      _updatePending(
        row.branchId,
        (widget.pendingByBranchId[row.branchId] ?? PendingBranchConfiguration(branchId: row.branchId, branchName: row.branchName))
            .copyWith(clearPromotion: true),
      );
      return;
    }

    final serviceId = widget.serviceId;
    final updatedAt = row.updatedAt;
    if (serviceId == null || updatedAt == null) {
      return;
    }

    try {
      await ref.read(serviceEditorProvider(serviceId).notifier).clearServicePromotion(
            branchId: row.branchId,
            expectedUpdatedAt: updatedAt,
          );
      if (mounted) {
        setState(() => _rowErrors.remove(row.branchId));
      }
    } on RpcFailure catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _rowErrors[row.branchId] = serviceCatalogMessageForRpc(error));
    }
  }

  Future<void> _openCopyDialog() async {
    final copied = await showCopyConfigurationDialog(context, ref, serviceId: widget.serviceId);
    if (!copied || !mounted || widget.serviceId == null) {
      return;
    }
    await ref.read(serviceEditorProvider(widget.serviceId).notifier).reloadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleBranches;
    final colors = context.colors;
    final typography = context.typography;

    if (visible.isEmpty) {
      return AppEmptyState(
        variant: AppEmptyStateVariant.firstRun,
        title: 'No branches selected',
        description: widget.isCreateMode
            ? 'Assign this service to at least one branch to configure per-branch pricing.'
            : 'Assign branches in the service details section above.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Per-branch configuration',
                style: typography.bodyStrong.copyWith(color: colors.textPrimary),
              ),
            ),
            if (widget.canManage && !widget.isCreateMode)
              AppButton(
                label: 'Copy configuration',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                leadingIcon: LucideIcons.copy,
                onPressed: _openCopyDialog,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        for (final row in visible) ...[
          _BranchConfigurationRow(
            row: row,
            defaultPriceWire: widget.defaultPriceWire,
            serviceId: widget.serviceId,
            canManage: widget.canManage,
            isCreateMode: widget.isCreateMode,
            submitted: _rowSubmitted[row.branchId] ?? false,
            error: _rowErrors[row.branchId],
            effectivePriceWire: _effectivePriceWire(row),
            onActiveChanged: (active) => _saveBranchSettings(row, active: active, priceOverride: row.priceOverride?.wireValue),
            onOverrideSave: (overrideWire) => _saveBranchSettings(
              row,
              active: row.isActive,
              priceOverride: overrideWire?.trim().isEmpty ?? true ? null : overrideWire?.trim(),
            ),
            onPromotionSave: (promotion) => _savePromotion(row, promotion),
            onPromotionClear: () => _clearPromotion(row),
            onSubmitted: () => setState(() => _rowSubmitted[row.branchId] = true),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
      ],
    );
  }
}

class _BranchConfigurationRow extends ConsumerStatefulWidget {
  const _BranchConfigurationRow({
    required this.row,
    required this.defaultPriceWire,
    required this.serviceId,
    required this.canManage,
    required this.isCreateMode,
    required this.submitted,
    required this.error,
    required this.effectivePriceWire,
    required this.onActiveChanged,
    required this.onOverrideSave,
    required this.onPromotionSave,
    required this.onPromotionClear,
    required this.onSubmitted,
  });

  final ServiceBranchConfig row;
  final String defaultPriceWire;
  final String? serviceId;
  final bool canManage;
  final bool isCreateMode;
  final bool submitted;
  final String? error;
  final String effectivePriceWire;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<String?> onOverrideSave;
  final ValueChanged<ServicePromotion> onPromotionSave;
  final VoidCallback onPromotionClear;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_BranchConfigurationRow> createState() => _BranchConfigurationRowState();
}

class _BranchConfigurationRowState extends ConsumerState<_BranchConfigurationRow> {
  late bool _active;
  Decimal? _override;
  String? _overrideError;

  @override
  void initState() {
    super.initState();
    _active = widget.row.isActive;
    _override = widget.row.priceOverride == null ? null : Decimal.parse(widget.row.priceOverride!.wireValue);
  }

  @override
  void didUpdateWidget(covariant _BranchConfigurationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row != widget.row) {
      _active = widget.row.isActive;
      _override = widget.row.priceOverride == null ? null : Decimal.parse(widget.row.priceOverride!.wireValue);
    }
  }

  Future<void> _handleOverrideSave() async {
    final wire = _override == null ? null : Money.parse(_override!.toStringAsFixed(2)).wireValue;
    if (wire != null) {
      final error = ServiceFormValidation.validateDefaultPrice(wire);
      if (error != null) {
        setState(() => _overrideError = error);
        return;
      }
    }
    setState(() => _overrideError = null);
    widget.onOverrideSave(wire);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final branchLabel = widget.row.branchName ?? 'Branch ${widget.row.branchId}';

    return AppCard(
      variant: AppCardVariant.flat,
      padding: AppCardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  branchLabel,
                  style: typography.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              AppBadge(
                color: _active ? AppBadgeColor.success : AppBadgeColor.neutral,
                child: Text(_active ? 'Active' : 'Inactive'),
              ),
            ],
          ),
          if (widget.error != null) ...[
            const SizedBox(height: AppSpacing.s3),
            AppAlert(variant: AppAlertVariant.danger, title: widget.error!),
          ],
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Branch status',
            helperText: 'Inactive services cannot be selected on invoices at this branch.',
            child: AppSwitch(
              label: _active ? 'Active at this branch' : 'Inactive at this branch',
              value: _active,
              disabled: !widget.canManage,
              onChanged: (value) {
                setState(() => _active = value);
                widget.onActiveChanged(value);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          AppFormField(
            label: 'Price override',
            helperText: 'Leave empty to use the service default price (${widget.defaultPriceWire}).',
            error: widget.submitted ? _overrideError : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppMoneyField(
                    value: _override,
                    disabled: !widget.canManage,
                    invalid: widget.submitted && _overrideError != null,
                    hintText: 'Default',
                    onValueChange: (value) => setState(() {
                      _override = value;
                      _overrideError = null;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),
                AppButton(
                  label: 'Apply',
                  size: AppButtonSize.sm,
                  disabled: !widget.canManage,
                  onPressed: widget.canManage
                      ? () {
                          widget.onSubmitted();
                          _handleOverrideSave();
                        }
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          _BranchPricePreview(
            serviceId: widget.serviceId,
            branchId: widget.row.branchId,
            defaultPriceWire: widget.defaultPriceWire,
            priceOverrideWire: _override == null ? null : Money.parse(_override!.toStringAsFixed(2)).wireValue,
            promotion: widget.row.promotion,
          ),
          const SizedBox(height: AppSpacing.s4),
          PromotionEditor(
            promotion: widget.row.promotion,
            effectivePriceWire: widget.effectivePriceWire,
            disabled: !widget.canManage,
            submitted: widget.submitted,
            onSave: (promotion) {
              widget.onSubmitted();
              widget.onPromotionSave(promotion);
            },
            onClear: () {
              widget.onSubmitted();
              widget.onPromotionClear();
            },
          ),
        ],
      ),
    );
  }
}

class _BranchPricePreview extends ConsumerStatefulWidget {
  const _BranchPricePreview({
    required this.branchId,
    required this.defaultPriceWire,
    this.serviceId,
    this.priceOverrideWire,
    this.promotion,
  });

  final String? serviceId;
  final String branchId;
  final String defaultPriceWire;
  final String? priceOverrideWire;
  final ServicePromotion? promotion;

  @override
  ConsumerState<_BranchPricePreview> createState() => _BranchPricePreviewState();
}

class _BranchPricePreviewState extends ConsumerState<_BranchPricePreview> {
  String? _label;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _BranchPricePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serviceId != widget.serviceId ||
        oldWidget.branchId != widget.branchId ||
        oldWidget.defaultPriceWire != widget.defaultPriceWire ||
        oldWidget.priceOverrideWire != widget.priceOverrideWire ||
        oldWidget.promotion != widget.promotion) {
      _loadPreview();
    }
  }

  Future<void> _loadPreview() async {
    final serviceId = widget.serviceId;
    if (serviceId == null || serviceId.isEmpty) {
      setState(() => _label = _draftPreviewLabel());
      return;
    }

    setState(() => _loading = true);
    try {
      final eligibility = await ref.read(serviceCatalogRepositoryProvider).resolveEffectivePrice(
            serviceId: serviceId,
            branchId: widget.branchId,
          );
      if (!mounted) {
        return;
      }
      final price = eligibility.price;
      setState(() {
        _loading = false;
        _label = price == null ? 'Not eligible' : ServicePricePreview.formatWithRule(price);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _label = _draftPreviewLabel();
      });
    }
  }

  String _draftPreviewLabel() {
    final today = DateTime.now();
    final promotion = widget.promotion;
    if (promotion != null && promotion.isActiveOn(today)) {
      return '${ServicePricePreview.formatUnitPrice(promotion.price)} (promo)';
    }
    final override = widget.priceOverrideWire;
    if (override != null && override.isNotEmpty) {
      final money = Money.tryParse(override);
      if (money != null) {
        return '${ServicePricePreview.formatUnitPrice(money)} (override)';
      }
    }
    final fallback = Money.tryParse(widget.defaultPriceWire);
    return fallback == null ? widget.defaultPriceWire : ServicePricePreview.formatUnitPrice(fallback);
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final colors = context.colors;

    return Row(
      children: [
        Icon(LucideIcons.circleDollarSign, size: 16, color: colors.textSecondary),
        const SizedBox(width: AppSpacing.s2),
        if (_loading)
          const SizedBox(width: 16, height: 16, child: AppSpinner(size: AppSpinnerSize.sm))
        else
          Expanded(
            child: Text(
              'Effective price today: ${_label ?? '—'}',
              style: typography.tabular(typography.bodySm).copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
