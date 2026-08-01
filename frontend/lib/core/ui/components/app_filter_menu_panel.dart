import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_divider.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Minimum panel width (web `min-w-[14rem]`).
const _kFilterMenuPanelMinWidth = 224.0;

/// Single option in an [AppFilterMenuPanel] section (web `FilterMenuOption`).
@immutable
class AppFilterMenuOption {
  const AppFilterMenuOption({required this.value, required this.label});

  final String value;
  final String label;
}

/// Radio listbox section (web `FilterMenuSection`).
@immutable
class AppFilterMenuSection {
  const AppFilterMenuSection({
    required this.id,
    required this.label,
    required this.value,
    required this.options,
    required this.onChange,
  });

  final String id;
  final String label;
  final String value;
  final List<AppFilterMenuOption> options;
  final ValueChanged<String> onChange;
}

/// Single- or multi-section filter popover body (web `FilterMenuPanel`).
class AppFilterMenuPanel extends StatelessWidget {
  const AppFilterMenuPanel({required this.sections, super.key});

  final List<AppFilterMenuSection> sections;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _kFilterMenuPanelMinWidth),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < sections.length; index++) ...[
              if (index > 0) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.space2),
                  child: AppDivider(),
                ),
              ],
              _AppFilterMenuSectionBlock(section: sections[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppFilterMenuSectionBlock extends StatelessWidget {
  const _AppFilterMenuSectionBlock({required this.section});

  final AppFilterMenuSection section;

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
        Semantics(
          container: true,
          label: section.label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final option in section.options)
                _AppFilterMenuOptionRow(
                  label: option.label,
                  selected: option.value == section.value,
                  onSelect: () => section.onChange(option.value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppFilterMenuOptionRow extends StatefulWidget {
  const _AppFilterMenuOptionRow({
    required this.label,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;

  @override
  State<_AppFilterMenuOptionRow> createState() => _AppFilterMenuOptionRowState();
}

class _AppFilterMenuOptionRowState extends State<_AppFilterMenuOptionRow> {
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
