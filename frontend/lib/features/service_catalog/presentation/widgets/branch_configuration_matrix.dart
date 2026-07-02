import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_branch_config.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/promotion_editor.dart';

/// Per-branch activation, override, and promotion matrix for the service editor (US3+US4).
class BranchConfigurationMatrix extends StatelessWidget {
  const BranchConfigurationMatrix({
    super.key,
    required this.branches,
    required this.defaultPrice,
    required this.onConfigureBranch,
    required this.onSetPromotion,
    required this.onClearPromotion,
    this.isSaving = false,
  });

  final List<ServiceBranchConfig> branches;
  final Money defaultPrice;
  final bool isSaving;
  final Future<void> Function({
    required ServiceBranchConfig branch,
    required bool active,
    required String? priceOverride,
  })
  onConfigureBranch;
  final Future<void> Function({
    required ServiceBranchConfig branch,
    required String price,
    required DateTime startDate,
    required DateTime endDate,
  })
  onSetPromotion;
  final Future<void> Function({required ServiceBranchConfig branch}) onClearPromotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (branches.isEmpty) {
      return Text('No assigned branches are visible for your current branch access.', style: theme.textTheme.bodySmall);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Branch configuration', style: theme.textTheme.titleSmall),
        const SizedBox(height: SpacingTokens.xs),
        Text(
          'Set per-branch activation and price overrides. Leave override empty to use the default price.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: SpacingTokens.md),
        ...branches.map(
          (branch) => _BranchConfigurationRow(
            key: ValueKey(branch.serviceBranchId),
            branch: branch,
            defaultPrice: defaultPrice,
            isSaving: isSaving,
            onConfigureBranch: onConfigureBranch,
            onSetPromotion: onSetPromotion,
            onClearPromotion: onClearPromotion,
          ),
        ),
      ],
    );
  }
}

class _BranchConfigurationRow extends StatefulWidget {
  const _BranchConfigurationRow({
    super.key,
    required this.branch,
    required this.defaultPrice,
    required this.isSaving,
    required this.onConfigureBranch,
    required this.onSetPromotion,
    required this.onClearPromotion,
  });

  final ServiceBranchConfig branch;
  final Money defaultPrice;
  final bool isSaving;
  final Future<void> Function({
    required ServiceBranchConfig branch,
    required bool active,
    required String? priceOverride,
  })
  onConfigureBranch;
  final Future<void> Function({
    required ServiceBranchConfig branch,
    required String price,
    required DateTime startDate,
    required DateTime endDate,
  })
  onSetPromotion;
  final Future<void> Function({required ServiceBranchConfig branch}) onClearPromotion;

  @override
  State<_BranchConfigurationRow> createState() => _BranchConfigurationRowState();
}

class _BranchConfigurationRowState extends State<_BranchConfigurationRow> {
  late final TextEditingController _overrideController;
  bool _showPromotion = false;

  @override
  void initState() {
    super.initState();
    _overrideController = TextEditingController(text: widget.branch.priceOverride?.wireValue ?? '');
  }

  @override
  void didUpdateWidget(covariant _BranchConfigurationRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextOverride = widget.branch.priceOverride?.wireValue ?? '';
    if (oldWidget.branch.priceOverride?.wireValue != widget.branch.priceOverride?.wireValue &&
        _overrideController.text != nextOverride) {
      _overrideController.text = nextOverride;
    }
  }

  @override
  void dispose() {
    _overrideController.dispose();
    super.dispose();
  }

  String get _effectivePrice => (widget.branch.priceOverride ?? widget.defaultPrice).wireValue;

  Future<void> _saveBranch({required bool active}) async {
    final trimmed = _overrideController.text.trim();
    final priceOverride = trimmed.isEmpty ? null : trimmed;
    if (priceOverride != null && Money.tryParse(priceOverride) == null) {
      return;
    }
    await widget.onConfigureBranch(branch: widget.branch, active: active, priceOverride: priceOverride);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branchName = widget.branch.branchName ?? widget.branch.branchId;

    return Card(
      margin: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Padding(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 560;
            final header = isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(branchName, style: theme.textTheme.titleSmall),
                      const SizedBox(height: SpacingTokens.sm),
                      AppSwitch(
                        label: 'Active',
                        value: widget.branch.isActive,
                        enabled: !widget.isSaving,
                        onChanged: (active) => _saveBranch(active: active),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: Text(branchName, style: theme.textTheme.titleSmall)),
                      AppSwitch(
                        label: 'Active',
                        value: widget.branch.isActive,
                        enabled: !widget.isSaving,
                        onChanged: (active) => _saveBranch(active: active),
                      ),
                    ],
                  );

            final actions = isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppButton(
                        label: 'Save branch settings',
                        onPressed: widget.isSaving ? null : () => _saveBranch(active: widget.branch.isActive),
                        isLoading: widget.isSaving,
                      ),
                      const SizedBox(height: SpacingTokens.sm),
                      AppButton(
                        label: _showPromotion ? 'Hide promotion' : 'Promotion',
                        variant: AppButtonVariant.secondary,
                        onPressed: widget.isSaving ? null : () => setState(() => _showPromotion = !_showPromotion),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      AppButton(
                        label: 'Save branch settings',
                        onPressed: widget.isSaving ? null : () => _saveBranch(active: widget.branch.isActive),
                        isLoading: widget.isSaving,
                      ),
                      const SizedBox(width: SpacingTokens.sm),
                      AppButton(
                        label: _showPromotion ? 'Hide promotion' : 'Promotion',
                        variant: AppButtonVariant.secondary,
                        onPressed: widget.isSaving ? null : () => setState(() => _showPromotion = !_showPromotion),
                      ),
                    ],
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: SpacingTokens.sm),
                AppTextField(
                  label: 'Price override',
                  controller: _overrideController,
                  enabled: !widget.isSaving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  description: 'Empty uses default (${widget.defaultPrice.wireValue}).',
                ),
                const SizedBox(height: SpacingTokens.sm),
                actions,
                if (_showPromotion) ...[
                  const SizedBox(height: SpacingTokens.md),
                  PromotionEditor(
                    key: ValueKey('promo-${widget.branch.serviceBranchId}-${widget.branch.promotion?.wirePrice}'),
                    effectivePrice: _effectivePrice,
                    initialPromotion: widget.branch.promotion,
                    isSaving: widget.isSaving,
                    onSave: ({required price, required startDate, required endDate}) {
                      return widget.onSetPromotion(
                        branch: widget.branch,
                        price: price,
                        startDate: startDate,
                        endDate: endDate,
                      );
                    },
                    onClear: () => widget.onClearPromotion(branch: widget.branch),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
