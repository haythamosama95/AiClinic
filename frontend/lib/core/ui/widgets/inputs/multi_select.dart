import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/combobox.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Multi-value select with chips and filterable dropdown.
class AppMultiSelect extends StatefulWidget {
  const AppMultiSelect({
    super.key,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder = 'Select items',
    this.value = const [],
    this.options = const [],
    this.allLabel = 'All branches',
    this.onValueChange,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final String placeholder;
  final List<AppComboboxItem> value;
  final List<AppComboboxItem> options;
  final String allLabel;
  final ValueChanged<List<AppComboboxItem>>? onValueChange;

  @override
  State<AppMultiSelect> createState() => _AppMultiSelectState();
}

class _AppMultiSelectState extends State<AppMultiSelect> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _open = false;
  bool _focused = false;

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Set<String> get _selectedIds => widget.value.map((v) => v.id).toSet();

  List<AppComboboxItem> get _filtered {
    final q = _queryController.text.toLowerCase();
    return widget.options.where((o) {
      if (_selectedIds.contains(o.id)) return false;
      return o.label.toLowerCase().contains(q) ||
          (o.meta?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _toggle(AppComboboxItem item) {
    if (item.disabled) return;
    final exists = _selectedIds.contains(item.id);
    final next = exists
        ? widget.value.where((v) => v.id != item.id).toList()
        : [...widget.value, item];
    widget.onValueChange?.call(next);
    _queryController.clear();
    _focusNode.requestFocus();
    setState(() {});
  }

  void _remove(String id) {
    widget.onValueChange?.call(widget.value.where((v) => v.id != id).toList());
    setState(() {});
  }

  void _selectAll() {
    widget.onValueChange?.call(
      widget.options.where((o) => !o.disabled).toList(),
    );
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final filtered = _filtered;

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (f) => setState(() {
        _focused = f;
        if (f) _open = true;
      }),
      child: AppPopover(
        open: _open && !widget.disabled,
        onOpenChange: (v) => setState(() => _open = v),
        matchTriggerWidth: true,
        contentPadding: EdgeInsets.zero,
        trigger: Container(
          constraints: BoxConstraints(
            minHeight: AppInputStyles.height(widget.size),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          decoration: AppInputStyles.wrapperDecoration(
            context,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            focused: _focused || _open,
          ),
          child: Wrap(
            spacing: AppSpacing.s1,
            runSpacing: AppSpacing.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in widget.value)
                _SelectionChip(
                  label: item.label,
                  disabled: widget.disabled,
                  onRemove: () => _remove(item.id),
                ),
              SizedBox(
                width: widget.value.isEmpty ? double.infinity : 120,
                child: TextField(
                  controller: _queryController,
                  enabled: !widget.disabled,
                  style: AppInputStyles.textStyle(
                    context,
                    widget.size,
                  ).copyWith(color: colors.textPrimary),
                  cursorColor: colors.borderFocus,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.value.isEmpty ? widget.placeholder : null,
                    hintStyle: AppInputStyles.textStyle(
                      context,
                      widget.size,
                    ).copyWith(color: colors.textPlaceholder),
                  ),
                  onChanged: (_) => setState(() => _open = true),
                  onTap: () => setState(() => _open = true),
                ),
              ),
            ],
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _selectAll,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s2,
                    ),
                    child: Text(
                      widget.allLabel,
                      style: typography.body.copyWith(color: colors.textLink),
                    ),
                  ),
                ),
              ),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  child: Center(
                    child: Text(
                      'No more options',
                      style: typography.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                )
              else
                for (final item in filtered)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: item.disabled ? null : () => _toggle(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s3,
                          vertical: AppSpacing.s2,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.label,
                                style: typography.body.copyWith(
                                  color: item.disabled
                                      ? colors.textDisabled
                                      : colors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.meta != null)
                              Text(
                                item.meta!,
                                style: typography.caption.copyWith(
                                  color: colors.textTertiary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
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

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({
    required this.label,
    required this.disabled,
    required this.onRemove,
  });

  final String label;
  final bool disabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s2,
        vertical: AppSpacing.s0_5,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: typography.bodySm.copyWith(color: colors.textPrimary),
          ),
          if (!disabled) ...[
            const SizedBox(width: AppSpacing.s1),
            InkWell(
              onTap: onRemove,
              borderRadius: AppRadius.smAll,
              child: Icon(Icons.close, size: 14, color: colors.iconMuted),
            ),
          ],
        ],
      ),
    );
  }
}
