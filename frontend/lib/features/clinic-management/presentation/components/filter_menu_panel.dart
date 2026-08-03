import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Single option in a [FilterMenuPanel] section (web `FilterMenuOption`).
@immutable
class FilterMenuOption {
  const FilterMenuOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Radio listbox section (web `FilterMenuSection`).
@immutable
class FilterMenuSection {
  const FilterMenuSection({
    required this.id,
    required this.label,
    required this.value,
    required this.options,
    required this.onChange,
  });

  final String id;
  final String label;
  final String value;
  final List<FilterMenuOption> options;
  final ValueChanged<String> onChange;
}

/// Single- or multi-section filter popover body (web `FilterMenuPanel`).
class FilterMenuPanel extends StatelessWidget {
  const FilterMenuPanel({
    required this.sections,
    super.key,
  });

  final List<FilterMenuSection> sections;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 224),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < sections.length; index++) ...[
              if (index > 0) ...[
                const SizedBox(height: AppSpacing.space2),
                SizedBox(
                  height: 1,
                  child: ColoredBox(color: context.appColors.borderSubtle),
                ),
                const SizedBox(height: AppSpacing.space2),
              ],
              _FilterMenuSectionBlock(section: sections[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterMenuSectionBlock extends StatelessWidget {
  const _FilterMenuSectionBlock({required this.section});

  final FilterMenuSection section;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space2,
            vertical: 6,
          ),
          child: Text(
            section.label,
            style: AppTypography.overline(context).copyWith(color: colors.textTertiary),
          ),
        ),
        for (final option in section.options)
          _FilterMenuOptionRow(
            label: option.label,
            selected: option.value == section.value,
            onSelect: () => section.onChange(option.value),
          ),
      ],
    );
  }
}

class _FilterMenuOptionRow extends StatefulWidget {
  const _FilterMenuOptionRow({
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;

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
    final foreground = widget.selected ? colors.textPrimary : colors.textSecondary;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: widget.onSelect,
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
                        ? Icon(Icons.check, size: 14, color: colors.actionPrimary)
                        : null,
                  ),
                  const SizedBox(width: AppSpacing.space2),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: AppTypography.bodySm(context).copyWith(
                        color: foreground,
                        fontWeight: widget.selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
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
