import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

const _kSmBreakpoint = 640.0;

/// Sort dropdown option (web `SortOption`).
@immutable
class AppSortOption {
  const AppSortOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Removable active-filter chip descriptor (web `ActiveFilter`).
@immutable
class AppActiveFilter {
  const AppActiveFilter({required this.id, required this.label, required this.onRemove});

  final String id;
  final String label;
  final VoidCallback onRemove;
}

/// Search, filter popover, sort menu, and active-filter chip strip (web `ListControlBar`).
class AppListControlBar extends StatefulWidget {
  const AppListControlBar({
    required this.searchPlaceholder,
    required this.searchAriaLabel,
    this.controller,
    this.searchValue,
    this.onSearchChange,
    this.debounceMs,
    required this.sortValue,
    required this.defaultSortValue,
    required this.sortOptions,
    required this.onSortChange,
    required this.sortAriaLabel,
    required this.filterMenu,
    this.filterActiveCount = 0,
    this.onClearFilters,
    this.activeFilters = const [],
    this.hasActiveFilters = false,
    this.onClearAll,
    super.key,
  });

  final String searchPlaceholder;
  final String searchAriaLabel;
  final TextEditingController? controller;
  final String? searchValue;
  final ValueChanged<String>? onSearchChange;
  final int? debounceMs;
  final String sortValue;
  final String defaultSortValue;
  final List<AppSortOption> sortOptions;
  final ValueChanged<String> onSortChange;
  final String sortAriaLabel;
  final Widget filterMenu;
  final int filterActiveCount;
  final VoidCallback? onClearFilters;
  final List<AppActiveFilter> activeFilters;
  final bool hasActiveFilters;
  final VoidCallback? onClearAll;

  @override
  State<AppListControlBar> createState() => _AppListControlBarState();
}

class _AppListControlBarState extends State<AppListControlBar> {
  TextEditingController? _internalController;

  TextEditingController get _searchController => widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController(text: widget.searchValue ?? '');
    }
  }

  @override
  void didUpdateWidget(covariant AppListControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextValue = widget.searchValue;
    if (nextValue == null || nextValue == oldWidget.searchValue) return;
    if (nextValue == _searchController.text) return;
    _searchController.text = nextValue;
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  bool get _sortIsCustom => widget.sortValue != widget.defaultSortValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= _kSmBreakpoint;
    final shellPadding = isWide ? AppSpacing.space5 : AppSpacing.space4;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: elevation.shadows1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(shellPadding),
              child: isWide ? _buildWideControls(context) : _buildNarrowControls(context),
            ),
            _ActiveFilterStrip(
              activeFilters: widget.activeFilters,
              hasActiveFilters: widget.hasActiveFilters,
              onClearAll: widget.onClearAll,
              horizontalPadding: shellPadding,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideControls(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _buildSearchInput()),
        const SizedBox(width: AppSpacing.space3),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildNarrowControls(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchInput(),
        const SizedBox(height: AppSpacing.space3),
        _buildActionButtons(context),
      ],
    );
  }

  Widget _buildSearchInput() {
    return Semantics(
      label: widget.searchAriaLabel,
      textField: true,
      child: AppSearchInput(
        controller: _searchController,
        placeholder: widget.searchPlaceholder,
        onValueChange: widget.onSearchChange,
        debounceMs: widget.debounceMs ?? 300,
        showShortcutHint: false,
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.space2,
      runSpacing: AppSpacing.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _FilterButton(
          activeCount: widget.filterActiveCount,
          filterMenu: widget.filterMenu,
          onClearFilters: widget.onClearFilters,
        ),
        _SortButton(
          sortAriaLabel: widget.sortAriaLabel,
          sortIsCustom: _sortIsCustom,
          sortValue: widget.sortValue,
          defaultSortValue: widget.defaultSortValue,
          sortOptions: widget.sortOptions,
          onSortChange: widget.onSortChange,
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.activeCount, required this.filterMenu, this.onClearFilters});

  final int activeCount;
  final Widget filterMenu;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final popoverWidth = math.min(288.0, MediaQuery.sizeOf(context).width - 32);

    return AppPopover(
      align: AppPopoverAlign.end,
      matchTriggerWidth: false,
      width: popoverWidth,
      triggerBuilder: (context, isOpen, onToggle) {
        return Semantics(
          button: true,
          expanded: isOpen,
          child: AppButton(
            variant: AppButtonVariant.secondary,
            leadingIcon: const Icon(Icons.tune, size: 15),
            onPressed: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Filter'),
                if (activeCount > 0) ...[
                  const SizedBox(width: AppSpacing.space1),
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.actionPrimary,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Center(
                        child: Text(
                          '$activeCount',
                          style: AppTypography.caption(context).copyWith(
                            color: colors.actionPrimaryFg,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filterMenu,
          if (activeCount > 0 && onClearFilters != null)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space2),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      onPressed: onClearFilters,
                      child: const Text('Clear filters'),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.sortAriaLabel,
    required this.sortIsCustom,
    required this.sortValue,
    required this.defaultSortValue,
    required this.sortOptions,
    required this.onSortChange,
  });

  final String sortAriaLabel;
  final bool sortIsCustom;
  final String sortValue;
  final String defaultSortValue;
  final List<AppSortOption> sortOptions;
  final ValueChanged<String> onSortChange;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppMenu(
      align: AppPopoverAlign.end,
      entries: [
        AppMenuSection(
          label: 'Sort by',
          items: [
            for (final option in sortOptions)
              AppMenuItem(
                id: option.value,
                label: option.label,
                checked: option.value == sortValue,
                icon: option.value == sortValue
                    ? Icon(Icons.check, size: 14, color: colors.actionPrimary)
                    : const SizedBox(width: 14, height: 14),
                onSelect: () => onSortChange(option.value),
              ),
          ],
        ),
        if (sortIsCustom) ...[
          const AppMenuSeparator(),
          AppMenuItem(id: 'clear-sorting', label: 'Clear sorting', onSelect: () => onSortChange(defaultSortValue)),
        ],
      ],
      trigger: Semantics(
        button: true,
        label: sortAriaLabel,
        child: Material(
          color: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AppButton(
                variant: AppButtonVariant.secondary,
                leadingIcon: const Icon(Icons.swap_vert, size: 15),
                child: const Text('Sort'),
              ),
              if (sortIsCustom)
                PositionedDirectional(
                  top: 6,
                  end: 6,
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: colors.actionPrimary, shape: BoxShape.circle),
                      child: const SizedBox(width: 6, height: 6),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterStrip extends StatelessWidget {
  const _ActiveFilterStrip({
    required this.activeFilters,
    required this.hasActiveFilters,
    required this.horizontalPadding,
    this.onClearAll,
  });

  final List<AppActiveFilter> activeFilters;
  final bool hasActiveFilters;
  final double horizontalPadding;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = AppMotion.prefersReducedMotion(context);
    final duration = reducedMotion ? Duration.zero : const Duration(milliseconds: 180);

    return ClipRect(
      child: AnimatedSize(
        duration: duration,
        curve: AppMotion.outCurve,
        alignment: Alignment.topCenter,
        clipBehavior: Clip.hardEdge,
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: AppMotion.outCurve,
          switchOutCurve: AppMotion.inCurve,
          transitionBuilder: (child, animation) {
            if (reducedMotion) return child;
            return FadeTransition(opacity: animation, child: child);
          },
          child: activeFilters.isEmpty
              ? const SizedBox.shrink(key: ValueKey<String>('app-list-control-bar-filters-empty'))
              : _ActiveFilterStripContent(
                  key: const ValueKey<String>('app-list-control-bar-filters'),
                  activeFilters: activeFilters,
                  hasActiveFilters: hasActiveFilters,
                  horizontalPadding: horizontalPadding,
                  onClearAll: onClearAll,
                ),
        ),
      ),
    );
  }
}

class _ActiveFilterStripContent extends StatelessWidget {
  const _ActiveFilterStripContent({
    required this.activeFilters,
    required this.hasActiveFilters,
    required this.horizontalPadding,
    this.onClearAll,
    super.key,
  });

  final List<AppActiveFilter> activeFilters;
  final bool hasActiveFilters;
  final double horizontalPadding;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final showClearAll = hasActiveFilters && onClearAll != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.8))),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.tune, size: 13, color: colors.iconMuted),
                  Text(
                    'Filtered by',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500, color: colors.textTertiary),
                  ),
                  for (final filter in activeFilters)
                    AppChip(
                      key: ValueKey<String>(filter.id),
                      removable: true,
                      onRemove: filter.onRemove,
                      child: Text(filter.label),
                    ),
                ],
              ),
            ),
            if (showClearAll) ...[
              const SizedBox(width: AppSpacing.space2),
              AppButton(
                variant: AppButtonVariant.ghost,
                size: AppButtonSize.sm,
                onPressed: onClearAll,
                child: Text(
                  'Clear all',
                  style: AppTypography.caption(context).copyWith(fontWeight: FontWeight.w500, color: colors.textLink),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
