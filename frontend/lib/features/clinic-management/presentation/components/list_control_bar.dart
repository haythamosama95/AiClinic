import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

class _ListControlBarCopy {
  const _ListControlBarCopy({
    required this.filter,
    required this.sort,
    required this.sortBy,
    required this.clearSorting,
    required this.filteredBy,
    required this.clearAll,
  });

  final String filter;
  final String sort;
  final String sortBy;
  final String clearSorting;
  final String filteredBy;
  final String clearAll;
}

const _copyEn = _ListControlBarCopy(
  filter: 'Filter',
  sort: 'Sort',
  sortBy: 'Sort by',
  clearSorting: 'Clear sorting',
  filteredBy: 'Filtered by',
  clearAll: 'Clear all',
);

const _copyAr = _ListControlBarCopy(
  filter: 'تصفية',
  sort: 'ترتيب',
  sortBy: 'ترتيب حسب',
  clearSorting: 'مسح الترتيب',
  filteredBy: 'مُصفّى حسب',
  clearAll: 'مسح الكل',
);

_ListControlBarCopy _copyFor(String locale) => locale == 'ar' ? _copyAr : _copyEn;

/// Sort dropdown option (web `SortOption`).
@immutable
class ListControlSortOption {
  const ListControlSortOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Removable active-filter chip descriptor (web `ActiveFilter`).
@immutable
class ListControlActiveFilterChip {
  const ListControlActiveFilterChip({required this.id, required this.label});

  final String id;
  final String label;
}

/// Search, filter popover, sort menu, and active-filter chip strip (web `ListControlBar`).
class ListControlBar extends StatefulWidget {
  const ListControlBar({
    required this.searchPlaceholder,
    required this.searchAriaLabel,
    required this.searchQuery,
    required this.onSearchChange,
    required this.sortValue,
    required this.defaultSortValue,
    required this.sortOptions,
    required this.onSortChange,
    required this.sortAriaLabel,
    required this.filterPanel,
    this.filterActiveCount = 0,
    this.activeFilterChips = const [],
    this.onRemoveChip,
    this.onClearAllFilters,
    this.onClearSort,
    super.key,
  });

  final String searchPlaceholder;
  final String searchAriaLabel;
  final String searchQuery;
  final ValueChanged<String> onSearchChange;
  final String sortValue;
  final String defaultSortValue;
  final List<ListControlSortOption> sortOptions;
  final ValueChanged<String> onSortChange;
  final String sortAriaLabel;
  final Widget filterPanel;
  final int filterActiveCount;
  final List<ListControlActiveFilterChip> activeFilterChips;
  final ValueChanged<String>? onRemoveChip;
  final VoidCallback? onClearAllFilters;
  final VoidCallback? onClearSort;

  @override
  State<ListControlBar> createState() => _ListControlBarState();
}

class _ListControlBarState extends State<ListControlBar> {
  late final TextEditingController _searchController = TextEditingController(text: widget.searchQuery);

  @override
  void didUpdateWidget(covariant ListControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != oldWidget.searchQuery && widget.searchQuery != _searchController.text) {
      _searchController.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _sortIsCustom => widget.sortValue != widget.defaultSortValue;

  bool get _hasActiveFilters => widget.activeFilterChips.isNotEmpty || widget.searchQuery.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final elevation = context.appElevation;
    final copy = _copyFor(Localizations.localeOf(context).languageCode);
    final showChipStrip = widget.activeFilterChips.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.surfaceDefault, Color.lerp(colors.surfaceDefault, colors.surfaceSelected, 0.35)!],
        ),
        boxShadow: elevation.shadows1,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useRow = constraints.maxWidth >= 640;

                  final searchField = Semantics(
                    label: widget.searchAriaLabel,
                    child: AppSearchInput(
                      controller: _searchController,
                      placeholder: widget.searchPlaceholder,
                      showShortcutHint: false,
                      onChanged: widget.onSearchChange,
                    ),
                  );

                  final actions = Wrap(
                    spacing: AppSpacing.space2,
                    runSpacing: AppSpacing.space2,
                    children: [
                      _FilterButton(
                        label: copy.filter,
                        activeCount: widget.filterActiveCount,
                        panel: widget.filterPanel,
                      ),
                      _SortButton(
                        label: copy.sort,
                        sortByLabel: copy.sortBy,
                        clearSortingLabel: copy.clearSorting,
                        ariaLabel: widget.sortAriaLabel,
                        sortIsCustom: _sortIsCustom,
                        sortValue: widget.sortValue,
                        sortOptions: widget.sortOptions,
                        onSortChange: widget.onSortChange,
                        onClearSort: widget.onClearSort,
                      ),
                    ],
                  );

                  if (useRow) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: AppSpacing.space3),
                        actions,
                      ],
                    );
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      searchField,
                      const SizedBox(height: AppSpacing.space3),
                      actions,
                    ],
                  );
                },
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: showChipStrip
                  ? _ActiveFilterStrip(
                      filteredByLabel: copy.filteredBy,
                      clearAllLabel: copy.clearAll,
                      chips: widget.activeFilterChips,
                      showClearAll: _hasActiveFilters && widget.onClearAllFilters != null,
                      onRemoveChip: widget.onRemoveChip,
                      onClearAllFilters: widget.onClearAllFilters,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.label, required this.activeCount, required this.panel});

  final String label;
  final int activeCount;
  final Widget panel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return AppPopover(
      align: AppPopoverAlign.end,
      matchTriggerWidth: false,
      minWidth: 288,
      triggerBuilder: (context, isOpen, onToggle) => AppButton(
        variant: AppButtonVariant.secondary,
        leadingIcon: const Icon(Icons.tune, size: 15),
        onPressed: onToggle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (activeCount > 0) ...[
              const SizedBox(width: AppSpacing.space1),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.actionPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    '$activeCount',
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.actionPrimaryFg, fontWeight: FontWeight.w600, fontSize: 10, height: 1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      child: panel,
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({
    required this.label,
    required this.sortByLabel,
    required this.clearSortingLabel,
    required this.ariaLabel,
    required this.sortIsCustom,
    required this.sortValue,
    required this.sortOptions,
    required this.onSortChange,
    this.onClearSort,
  });

  final String label;
  final String sortByLabel;
  final String clearSortingLabel;
  final String ariaLabel;
  final bool sortIsCustom;
  final String sortValue;
  final List<ListControlSortOption> sortOptions;
  final ValueChanged<String> onSortChange;
  final VoidCallback? onClearSort;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final showClearSort = sortIsCustom && onClearSort != null;

    return AppMenu(
      align: AppPopoverAlign.end,
      entries: [
        AppMenuSection(
          label: sortByLabel,
          items: [
            for (final option in sortOptions)
              AppMenuItem(
                id: option.value,
                label: option.label,
                checked: option.value == sortValue,
                onSelect: () => onSortChange(option.value),
              ),
          ],
        ),
        if (showClearSort) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            id: 'clear-sort',
            label: clearSortingLabel,
            onSelect: onClearSort,
          ),
        ],
      ],
      trigger: Semantics(
        button: true,
        label: ariaLabel,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              leadingIcon: const Icon(Icons.swap_vert, size: 15),
              child: Text(label),
            ),
            if (sortIsCustom)
              PositionedDirectional(
                top: 6,
                end: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: colors.actionPrimary, shape: BoxShape.circle),
                  child: const SizedBox(width: 6, height: 6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveFilterStrip extends StatelessWidget {
  const _ActiveFilterStrip({
    required this.filteredByLabel,
    required this.clearAllLabel,
    required this.chips,
    required this.showClearAll,
    required this.onRemoveChip,
    required this.onClearAllFilters,
  });

  final String filteredByLabel;
  final String clearAllLabel;
  final List<ListControlActiveFilterChip> chips;
  final bool showClearAll;
  final ValueChanged<String>? onRemoveChip;
  final VoidCallback? onClearAllFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceSunken.withValues(alpha: 0.4),
        border: Border(top: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.8))),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4, vertical: AppSpacing.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.space2,
                runSpacing: AppSpacing.space2,
                children: [
                  Icon(Icons.tune, size: 13, color: colors.iconMuted),
                  Text(
                    filteredByLabel,
                    style: AppTypography.caption(
                      context,
                    ).copyWith(color: colors.textTertiary, fontWeight: FontWeight.w500),
                  ),
                  for (final chip in chips)
                    AppChip(
                      removable: true,
                      onRemove: onRemoveChip == null ? null : () => onRemoveChip!(chip.id),
                      child: Text(chip.label),
                    ),
                ],
              ),
            ),
            if (showClearAll)
              AppButton(
                variant: AppButtonVariant.link,
                size: AppButtonSize.sm,
                onPressed: onClearAllFilters,
                child: Text(clearAllLabel),
              ),
          ],
        ),
      ),
    );
  }
}
