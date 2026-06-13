import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/features/patients/presentation/models/patient_list_filters.dart';

final _sortPopoverMotion = FPopoverStyleDelta.delta(
  motion: FPopoverMotionDelta.delta(
    entranceDuration: Duration(milliseconds: 200),
    exitDuration: Duration(milliseconds: 150),
    scaleTween: Tween<double>(begin: 0.96, end: 1),
    fadeTween: Tween<double>(begin: 0, end: 1),
  ),
);

/// Sort popover for the patients list.
class PatientsSortButton extends StatefulWidget {
  const PatientsSortButton({required this.filters, required this.onFiltersChanged, super.key});

  final PatientListFilters filters;
  final ValueChanged<PatientListFilters> onFiltersChanged;

  @override
  State<PatientsSortButton> createState() => _PatientsSortButtonState();
}

class _PatientsSortButtonState extends State<PatientsSortButton> with SingleTickerProviderStateMixin {
  late final FPopoverController _controller = FPopoverController(vsync: this);
  var _isHovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectSort(PatientSortField field) {
    widget.onFiltersChanged(widget.filters.copyWith(sortField: field));
    _controller.hide();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;
    final isCustomSort = widget.filters.sortField != PatientSortField.nameAsc;

    return FPopover(
      control: FPopoverControl.managed(controller: _controller),
      style: _sortPopoverMotion,
      constraints: const FPortalConstraints(minWidth: 280, maxWidth: 320),
      popoverAnchor: Alignment.topCenter,
      childAnchor: Alignment.bottomCenter,
      popoverBuilder: (context, controller) =>
          _PatientsSortPanel(selected: widget.filters.sortField, onSelected: _selectSort),
      builder: (context, controller, child) => MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: FTappable(
          onPress: controller.toggle,
          child: IgnorePointer(child: child),
        ),
      ),
      child: Tooltip(
        message: 'Sort patients',
        child: SizedBox(
          width: 40,
          height: 40,
          child: Badge(
            isLabelVisible: isCustomSort,
            smallSize: 8,
            backgroundColor: colors.primary,
            child: Material(
              color: _isHovered ? colors.muted : colors.background,
              shape: CircleBorder(side: BorderSide(color: isCustomSort ? colors.primary : colors.border)),
              clipBehavior: Clip.antiAlias,
              child: Center(
                child: Icon(Icons.sort_outlined, color: isCustomSort ? colors.primary : colors.foreground, size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientsSortPanel extends StatelessWidget {
  const _PatientsSortPanel({required this.selected, required this.onSelected});

  final PatientSortField selected;
  final ValueChanged<PatientSortField> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.sm, SpacingTokens.xs),
            child: Text('Sort by', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          _SortSection(
            title: 'Alphabetical',
            icon: Icons.sort_by_alpha_outlined,
            options: const [
              _SortOption(
                field: PatientSortField.nameAsc,
                label: 'A to Z',
                subtitle: 'Alphabetical order',
                icon: Icons.arrow_downward_rounded,
              ),
              _SortOption(
                field: PatientSortField.nameDesc,
                label: 'Z to A',
                subtitle: 'Reverse alphabetical',
                icon: Icons.arrow_upward_rounded,
              ),
            ],
            selected: selected,
            onSelected: onSelected,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xs),
            child: Divider(height: 1, color: colors.border),
          ),
          _SortSection(
            title: 'Visit date',
            icon: Icons.event_outlined,
            options: const [
              _SortOption(
                field: PatientSortField.lastVisitDesc,
                label: 'Most recent first',
                subtitle: 'Newest visits on top',
                icon: Icons.schedule_outlined,
              ),
              _SortOption(
                field: PatientSortField.lastVisitAsc,
                label: 'Oldest first',
                subtitle: 'Earliest visits on top',
                icon: Icons.history_outlined,
              ),
            ],
            selected: selected,
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

class _SortSection extends StatelessWidget {
  const _SortSection({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final IconData icon;
  final List<_SortOption> options;
  final PatientSortField selected;
  final ValueChanged<PatientSortField> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colors.mutedForeground),
              const SizedBox(width: SpacingTokens.xs),
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.xs),
          for (final option in options) ...[
            _SortOptionTile(
              option: option,
              isSelected: selected == option.field,
              onTap: () => onSelected(option.field),
            ),
          ],
        ],
      ),
    );
  }
}

@immutable
class _SortOption {
  const _SortOption({required this.field, required this.label, required this.subtitle, required this.icon});

  final PatientSortField field;
  final String label;
  final String subtitle;
  final IconData icon;
}

class _SortOptionTile extends StatefulWidget {
  const _SortOptionTile({required this.option, required this.isSelected, required this.onTap});

  final _SortOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_SortOptionTile> createState() => _SortOptionTileState();
}

class _SortOptionTileState extends State<_SortOptionTile> {
  var _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.semanticColors;
    final isSelected = widget.isSelected;

    final background = isSelected
        ? Color.alphaBlend(colors.primary.withValues(alpha: 0.1), colors.background)
        : _isHovered
        ? colors.muted.withValues(alpha: 0.5)
        : Colors.transparent;

    final borderColor = isSelected ? colors.primary.withValues(alpha: 0.35) : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.xs),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.sm),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: isSelected ? colors.primary.withValues(alpha: 0.12) : colors.muted.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(SpacingTokens.xs),
                      child: Icon(
                        widget.option.icon,
                        size: 18,
                        color: isSelected ? colors.primary : colors.mutedForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.option.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? colors.primary : colors.foreground,
                          ),
                        ),
                        Text(
                          widget.option.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isSelected ? 1 : 0,
                    child: Icon(Icons.check_circle_rounded, size: 20, color: colors.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
