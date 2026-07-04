import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/billing/domain/money.dart';
import 'package:ai_clinic/features/service_catalog/domain/pending_branch_configuration.dart';
import 'package:ai_clinic/features/service_catalog/domain/service_promotion.dart';
import 'package:ai_clinic/features/service_catalog/presentation/models/service_form_draft_snapshot.dart';
import 'package:ai_clinic/features/service_catalog/presentation/widgets/promotion_editor.dart';
import 'package:ai_clinic/features/settings/domain/branch_list_item.dart';
import 'package:ai_clinic/features/settings/presentation/widgets/settings_section_card.dart';

/// Draft branch overrides and promotions shown while creating a service (015 US3+US4).
class ServiceCreateBranchConfigSection extends StatefulWidget {
  const ServiceCreateBranchConfigSection({
    super.key,
    required this.formSnapshot,
    required this.branches,
    required this.draftConfigs,
    required this.onDraftConfigsChanged,
    this.isSaving = false,
  });

  final ServiceFormDraftSnapshot formSnapshot;
  final List<BranchListItem> branches;
  final Map<String, PendingBranchConfiguration> draftConfigs;
  final ValueChanged<Map<String, PendingBranchConfiguration>> onDraftConfigsChanged;
  final bool isSaving;

  @override
  State<ServiceCreateBranchConfigSection> createState() => _ServiceCreateBranchConfigSectionState();
}

class _ServiceCreateBranchConfigSectionState extends State<ServiceCreateBranchConfigSection> {
  String? _selectedBranchId;
  bool _overridePriceEnabled = false;
  bool _promotionEnabled = false;
  late final TextEditingController _overrideController;

  @override
  void initState() {
    super.initState();
    _overrideController = TextEditingController();
    _overrideController.addListener(_onOverrideChanged);
  }

  @override
  void dispose() {
    _overrideController.removeListener(_onOverrideChanged);
    _overrideController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServiceCreateBranchConfigSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final assignedIds = _assignedBranchIds();
    if (_selectedBranchId != null && !assignedIds.contains(_selectedBranchId)) {
      _selectedBranchId = null;
      _overridePriceEnabled = false;
      _promotionEnabled = false;
      _overrideController.text = '';
    } else if (_selectedBranchId != null) {
      _syncFromDraft(_selectedBranchId!);
    }
    _syncDraftConfigsIfNeeded(assignedIds);
  }

  Set<String> _assignedBranchIds() {
    final activeBranches = widget.branches.where((branch) => branch.isActive).toList(growable: false);
    if (widget.formSnapshot.assignAllBranches) {
      return {for (final branch in activeBranches) branch.id};
    }
    return widget.formSnapshot.selectedBranchIds;
  }

  Map<String, PendingBranchConfiguration> _syncedDraftConfigs(Set<String> assignedIds) {
    final activeBranches = widget.branches.where((branch) => branch.isActive).toList(growable: false);
    final next = <String, PendingBranchConfiguration>{};
    for (final branchId in assignedIds) {
      final branch = activeBranches.where((item) => item.id == branchId).firstOrNull;
      next[branchId] =
          widget.draftConfigs[branchId] ??
          PendingBranchConfiguration(branchId: branchId, branchName: branch?.name ?? branchId);
    }
    return next;
  }

  void _syncDraftConfigsIfNeeded(Set<String> assignedIds) {
    final syncedConfigs = _syncedDraftConfigs(assignedIds);
    final assignedChanged =
        syncedConfigs.length != widget.draftConfigs.length ||
        syncedConfigs.keys.any((key) => !widget.draftConfigs.containsKey(key));
    if (assignedChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        widget.onDraftConfigsChanged(syncedConfigs);
      });
    }
  }

  PendingBranchConfiguration? _configFor(String branchId) {
    return _syncedDraftConfigs(_assignedBranchIds())[branchId];
  }

  void _syncFromDraft(String branchId) {
    final config = _configFor(branchId);
    if (config == null) {
      return;
    }
    final override = config.priceOverride ?? '';
    _overridePriceEnabled = override.isNotEmpty;
    _promotionEnabled = config.promotion != null;
    if (_overrideController.text != override) {
      _overrideController.text = override;
    }
  }

  void _updateDraft(PendingBranchConfiguration updated) {
    final assignedIds = _assignedBranchIds();
    final next = _syncedDraftConfigs(assignedIds);
    next[updated.branchId] = updated;
    widget.onDraftConfigsChanged(next);
  }

  void _onBranchSelected(String? branchId) {
    setState(() {
      _selectedBranchId = branchId;
      if (branchId == null) {
        _overridePriceEnabled = false;
        _promotionEnabled = false;
        _overrideController.text = '';
        return;
      }
      _syncFromDraft(branchId);
    });
  }

  void _onOverrideToggled(bool enabled) {
    setState(() => _overridePriceEnabled = enabled);
    final branchId = _selectedBranchId;
    if (branchId == null) {
      return;
    }
    if (!enabled) {
      _overrideController.text = '';
      _updateDraft(_configFor(branchId)!.copyWith(clearPriceOverride: true));
    }
  }

  void _onPromotionToggled(bool enabled) {
    setState(() => _promotionEnabled = enabled);
    final branchId = _selectedBranchId;
    if (branchId == null) {
      return;
    }
    if (!enabled) {
      _updateDraft(_configFor(branchId)!.copyWith(clearPromotion: true));
    }
  }

  void _onOverrideChanged() {
    final branchId = _selectedBranchId;
    if (branchId == null || !_overridePriceEnabled) {
      return;
    }
    final trimmed = _overrideController.text.trim();
    if (trimmed.isNotEmpty && Money.tryParse(trimmed) == null) {
      return;
    }
    _updateDraft(
      _configFor(
        branchId,
      )!.copyWith(priceOverride: trimmed.isEmpty ? null : trimmed, clearPriceOverride: trimmed.isEmpty),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultPrice = Money.tryParse(widget.formSnapshot.defaultPrice);
    if (defaultPrice == null) {
      return const SizedBox.shrink();
    }

    final assignedIds = _assignedBranchIds();
    if (assignedIds.isEmpty) {
      return const SizedBox.shrink();
    }

    _syncDraftConfigsIfNeeded(assignedIds);

    final activeBranches = widget.branches.where((branch) => branch.isActive).toList(growable: false);
    final branchItems = <String, String>{
      for (final branch in activeBranches.where((branch) => assignedIds.contains(branch.id)))
        branch.id: '${branch.name}${branch.code == null ? '' : ' (${branch.code})'}',
    };

    final selectedConfig = _selectedBranchId == null ? null : _configFor(_selectedBranchId!);
    final effectivePrice =
        (selectedConfig?.priceOverride != null && selectedConfig!.priceOverride!.isNotEmpty
            ? Money.tryParse(selectedConfig.priceOverride!)
            : null) ??
        defaultPrice;

    return SettingsSectionCard(
      title: 'Per branch configuration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Optionally override price or run a promotion for a specific branch.', style: theme.textTheme.bodySmall),
          const SizedBox(height: SpacingTokens.md),
          AppSelect<String>(
            label: 'Branch',
            hintText: 'Select a branch',
            items: branchItems,
            value: _selectedBranchId,
            enabled: !widget.isSaving,
            onChanged: _onBranchSelected,
          ),
          if (_selectedBranchId != null) ...[
            const SizedBox(height: SpacingTokens.lg),
            AppSwitch(
              label: 'Override price',
              value: _overridePriceEnabled,
              enabled: !widget.isSaving,
              onChanged: _onOverrideToggled,
            ),
            if (_overridePriceEnabled) ...[
              const SizedBox(height: SpacingTokens.sm),
              AppTextField(
                label: 'Branch price',
                controller: _overrideController,
                enabled: !widget.isSaving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                description: 'Empty uses default (${defaultPrice.wireValue}).',
              ),
            ],
            const SizedBox(height: SpacingTokens.md),
            AppSwitch(
              label: 'Run promotion',
              value: _promotionEnabled,
              enabled: !widget.isSaving,
              onChanged: _onPromotionToggled,
            ),
            if (_promotionEnabled) ...[
              const SizedBox(height: SpacingTokens.sm),
              PromotionEditor(
                key: ValueKey('promo-$_selectedBranchId-${selectedConfig?.promotion?.wirePrice}'),
                effectivePrice: effectivePrice.wireValue,
                initialPromotion: selectedConfig?.promotion,
                isSaving: widget.isSaving,
                onSave: ({required price, required startDate, required endDate}) async {
                  final promotion = ServicePromotion(price: Money.parse(price), startDate: startDate, endDate: endDate);
                  _updateDraft(_configFor(_selectedBranchId!)!.copyWith(promotion: promotion));
                },
                onClear: () async {
                  _updateDraft(_configFor(_selectedBranchId!)!.copyWith(clearPromotion: true));
                  setState(() => _promotionEnabled = false);
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
