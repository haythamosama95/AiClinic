import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_menu.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/theme/app_elevation.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';
import 'package:ai_clinic/features/patients/presentation/widgets/patient_active_filters_bar.dart';

const _kSmBreakpoint = 640.0;

/// Search, sort, and last-visit filter controls (web `ListControlBar` top region).
class PatientListControls extends StatefulWidget {
  const PatientListControls({
    required this.filters,
    required this.onSearchChange,
    required this.onSortChange,
    required this.onLastVisitChange,
    this.onClearFilters,
    this.activeFilters = const [],
    this.onClearAll,
    super.key,
  });

  final PatientListFilters filters;
  final ValueChanged<String> onSearchChange;
  final ValueChanged<PatientSortField> onSortChange;
  final ValueChanged<PatientLastVisitFilter> onLastVisitChange;
  final VoidCallback? onClearFilters;
  final List<({String id, String label, VoidCallback onRemove})> activeFilters;
  final VoidCallback? onClearAll;

  @override
  State<PatientListControls> createState() => _PatientListControlsState();
}

class _PatientListControlsState extends State<PatientListControls> {
  late final TextEditingController _searchController;
  var _filterOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.filters.searchText);
  }

  @override
  void didUpdateWidget(covariant PatientListControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filters.searchText != oldWidget.filters.searchText &&
        widget.filters.searchText != _searchController.text) {
      _searchController.text = widget.filters.searchText;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _lastVisitActive =>
      widget.filters.lastVisitFilter != PatientLastVisitFilter.any;

  bool get _sortIsCustom =>
      widget.filters.sortField != PatientSortField.nameAsc;

  void _closeFilterPopover() => setState(() => _filterOpen = false);

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
        boxShadow: elevation.shadowsFor(1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.x2l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(shellPadding),
              child: isWide
                  ? _buildWideControls(context)
                  : _buildNarrowControls(context),
            ),
            PatientActiveFiltersBar(
              active: widget.activeFilters,
              onClearAll: widget.onClearAll,
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
      label: 'Search patients',
      textField: true,
      child: AppSearchInput(
        controller: _searchController,
        placeholder: 'Search patients by name, MRN, email, or phone…',
        onValueChange: widget.onSearchChange,
        showShortcutHint: false,
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFilterButton(context),
        const SizedBox(width: AppSpacing.space2),
        _buildSortButton(context),
      ],
    );
  }

  Widget _buildFilterButton(BuildContext context) {
    final filterPopoverWidth = math.min(
      288.0,
      MediaQuery.sizeOf(context).width - 32,
    );

    return AppPopover(
      open: _filterOpen,
      onOpenChange: (open) => setState(() => _filterOpen = open),
      align: AppPopoverAlign.end,
      matchTriggerWidth: false,
      width: filterPopoverWidth,
      triggerBuilder: (context, isOpen, toggle) {
        return Semantics(
          button: true,
          expanded: isOpen,
          child: AppButton(
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.md,
            leadingIcon: const Icon(Icons.tune, size: 15),
            onPressed: toggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Filter'),
                if (_lastVisitActive) ...[
                  const SizedBox(width: AppSpacing.space1),
                  AppBadge(
                    label: '1',
                    color: BadgeColor.teal,
                    variant: BadgeVariant.solid,
                    size: BadgeSize.sm,
                  ),
                ],
              ],
            ),
          ),
        );
      },
      child: _PatientFilterMenu(
        selected: widget.filters.lastVisitFilter,
        showClearFilters: _lastVisitActive && widget.onClearFilters != null,
        onSelect: (filter) {
          widget.onLastVisitChange(filter);
          _closeFilterPopover();
        },
        onClearFilters: widget.onClearFilters == null
            ? null
            : () {
                widget.onClearFilters!();
                _closeFilterPopover();
              },
      ),
    );
  }

  Widget _buildSortButton(BuildContext context) {
    final colors = context.appColors;

    return AppMenu(
      align: AppPopoverAlign.end,
      trigger: Semantics(
        button: true,
        label: 'Sort patients',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AppButton(
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.md,
              leadingIcon: const Icon(Icons.swap_vert, size: 15),
              child: const Text('Sort'),
            ),
            if (_sortIsCustom)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: ExcludeSemantics(
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: colors.actionPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      entries: [
        AppMenuSection(
          label: 'Sort by',
          items: [
            for (final option in _patientSortOptions)
              AppMenuItem(
                id: option.$1.name,
                label: option.$2,
                checked: widget.filters.sortField == option.$1,
                onSelect: () => widget.onSortChange(option.$1),
              ),
          ],
        ),
        if (_sortIsCustom) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            id: 'clear-sorting',
            label: 'Clear sorting',
            onSelect: () => widget.onSortChange(PatientSortField.nameAsc),
          ),
        ],
      ],
    );
  }
}

class _PatientFilterMenu extends StatelessWidget {
  const _PatientFilterMenu({
    required this.selected,
    required this.onSelect,
    this.showClearFilters = false,
    this.onClearFilters,
  });

  final PatientLastVisitFilter selected;
  final ValueChanged<PatientLastVisitFilter> onSelect;
  final bool showClearFilters;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.space2),
          child: Semantics(
            container: true,
            label: 'Last visit',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space2,
                    vertical: 6,
                  ),
                  child: Text(
                    'Last visit',
                    style: AppTypography.overline(
                      context,
                    ).copyWith(color: colors.textTertiary),
                  ),
                ),
                for (final option in _patientLastVisitOptions)
                  _FilterMenuOptionRow(
                    label: option.$2,
                    selected: selected == option.$1,
                    onPressed: () => onSelect(option.$1),
                  ),
              ],
            ),
          ),
        ),
        if (showClearFilters && onClearFilters != null)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space2),
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
      ],
    );
  }
}

class _FilterMenuOptionRow extends StatefulWidget {
  const _FilterMenuOptionRow({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_FilterMenuOptionRow> createState() => _FilterMenuOptionRowState();
}

class _FilterMenuOptionRowState extends State<_FilterMenuOptionRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final background = widget.selected
        ? colors.surfaceSelected
        : (_hovered ? colors.surfaceHover : Colors.transparent);
    final foreground = widget.selected
        ? colors.textPrimary
        : colors.textSecondary;
    final labelStyle = widget.selected
        ? AppTypography.bodySm(
            context,
          ).copyWith(fontWeight: FontWeight.w500, color: foreground)
        : AppTypography.bodySm(context).copyWith(color: foreground);

    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AppPressable(
            onPressed: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space2,
                vertical: AppSpacing.space2,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: widget.selected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: colors.actionPrimary,
                          )
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Expanded(child: Text(widget.label, style: labelStyle)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _patientSortOptions = <(PatientSortField, String)>[
  (PatientSortField.nameAsc, 'Name (A → Z)'),
  (PatientSortField.nameDesc, 'Name (Z → A)'),
  (PatientSortField.lastVisitDesc, 'Last visit (newest)'),
  (PatientSortField.lastVisitAsc, 'Last visit (oldest)'),
];

const _patientLastVisitOptions = <(PatientLastVisitFilter, String)>[
  (PatientLastVisitFilter.any, 'Any time'),
  (PatientLastVisitFilter.last30Days, 'Last 30 days'),
  (PatientLastVisitFilter.last90Days, 'Last 90 days'),
  (PatientLastVisitFilter.over90Days, 'Over 90 days'),
  (PatientLastVisitFilter.never, 'Never visited'),
];
