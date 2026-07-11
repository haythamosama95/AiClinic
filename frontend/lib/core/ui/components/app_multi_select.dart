import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/core/ui/components/app_combobox.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Multi-select token field (web `MultiSelect`).
class AppMultiSelect extends StatefulWidget {
  const AppMultiSelect({
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder,
    this.value = const [],
    this.onValueChange,
    required this.options,
    this.allLabel,
    super.key,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final String? placeholder;
  final List<AppComboboxItem> value;
  final ValueChanged<List<AppComboboxItem>>? onValueChange;
  final List<AppComboboxItem> options;
  final String? allLabel;

  @override
  State<AppMultiSelect> createState() => _AppMultiSelectState();
}

class _AppMultiSelectState extends State<AppMultiSelect> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();

  var _open = false;
  var _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _focused = _focusNode.hasFocus;
      if (_focusNode.hasFocus) _open = true;
    });
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
  }

  Set<String> get _selectedIds => widget.value.map((item) => item.id).toSet();

  /// Hide the inline query field when every option is already selected and the
  /// user is not actively searching — otherwise [Wrap] leaves a blank second row.
  bool get _showQueryField => widget.value.isEmpty || _filtered.isNotEmpty || _controller.text.isNotEmpty || _focused;

  List<AppComboboxItem> get _filtered {
    final lower = _controller.text.toLowerCase();
    return widget.options.where((option) {
      if (_selectedIds.contains(option.id)) return false;
      if (lower.isEmpty) return true;
      return option.label.toLowerCase().contains(lower) || (option.meta?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  void _toggle(AppComboboxItem item) {
    if (item.disabled) return;
    final exists = _selectedIds.contains(item.id);
    final next = exists ? widget.value.where((v) => v.id != item.id).toList() : [...widget.value, item];
    widget.onValueChange?.call(next);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _remove(String id) {
    widget.onValueChange?.call(widget.value.where((v) => v.id != id).toList());
  }

  void _selectAll() {
    final all = widget.options.where((o) => !o.disabled).toList();
    widget.onValueChange?.call(all);
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = appInputMetrics(context, widget.size);
    final colors = context.appColors;
    final filtered = _filtered;
    final allLabel = widget.allLabel ?? 'All branches';

    final field = appWrapMaterialInput(
      TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: !widget.disabled,
        style: widget.disabled
            ? appInputDisabledTextStyle(context, widget.size)
            : appInputTextStyle(context, widget.size),
        cursorColor: colors.textPrimary,
        decoration: appBareInputDecoration(
          context,
          size: widget.size,
          disabled: widget.disabled,
          hintText: widget.value.isEmpty ? (widget.placeholder ?? 'Select items') : null,
        ),
        onChanged: (_) => setState(() => _open = true),
        onTap: () => setState(() => _open = true),
      ),
    );

    final listbox = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
        shrinkWrap: true,
        children: [
          AppPressable(
            onPressed: _selectAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
              child: Text(allLabel, style: AppTypography.body(context).copyWith(color: colors.textLink)),
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space4),
              child: Center(
                child: Text(
                  'No more options',
                  style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                ),
              ),
            )
          else
            for (final item in filtered)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: item.disabled ? null : () => _toggle(item),
                  child: Opacity(
                    opacity: item.disabled ? 0.6 : 1,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.label,
                              style: AppTypography.body(
                                context,
                              ).copyWith(color: item.disabled ? colors.textDisabled : colors.textPrimary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.meta != null)
                            Text(
                              item.meta!,
                              style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );

    return Semantics(
      identifier: widget.id,
      textField: true,
      enabled: !widget.disabled,
      child: AppPopover(
        open: _open && !widget.disabled,
        onOpenChange: _setOpen,
        minWidth: appPopoverListboxMinWidth,
        child: listbox,
        triggerBuilder: (context, isOpen, onToggle) => GestureDetector(
          onTap: widget.disabled
              ? null
              : () {
                  setState(() => _open = true);
                  if (_showQueryField) _focusNode.requestFocus();
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: double.infinity,
            constraints: BoxConstraints(minHeight: metrics.height),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.horizontalPadding,
              vertical: AppSpacing.space1 + AppSpacing.space05,
            ),
            decoration: appInputDecoration(
              context,
              size: widget.size,
              invalid: widget.invalid,
              disabled: widget.disabled,
              focused: _focused,
            ),
            child: widget.value.isEmpty
                ? field
                : Wrap(
                    spacing: AppSpacing.space1,
                    runSpacing: AppSpacing.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final item in widget.value)
                        AppChip(
                          removable: true,
                          disabled: widget.disabled,
                          onRemove: () => _remove(item.id),
                          child: Text(item.label),
                        ),
                      if (_showQueryField) SizedBox(width: 72, child: field),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
