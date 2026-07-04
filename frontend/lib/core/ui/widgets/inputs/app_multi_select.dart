import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/display/app_chip.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_autocomplete.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_popover_inputs_shared.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Multi-value select with removable chips and combobox popover.
class AppMultiSelect<T> extends StatefulWidget {
  const AppMultiSelect({
    required this.options,
    this.value = const [],
    this.onChanged,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder = 'Select items',
    this.allLabel = 'All branches',
    this.showSelectAll = true,
    this.focusNode,
    super.key,
  });

  final List<AppAutocompleteOption<T>> options;
  final List<AppAutocompleteOption<T>> value;
  final ValueChanged<List<AppAutocompleteOption<T>>>? onChanged;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final String placeholder;
  final String allLabel;
  final bool showSelectAll;
  final FocusNode? focusNode;

  @override
  State<AppMultiSelect<T>> createState() => _AppMultiSelectState<T>();
}

class _AppMultiSelectState<T> extends State<AppMultiSelect<T>> {
  late AppPopoverController _popoverController;
  late TextEditingController _queryController;
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _popoverController = AppPopoverController();
    _queryController = TextEditingController();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
    _queryController.addListener(() {
      setState(() => _query = _queryController.text);
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _queryController.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    _popoverController.dispose();
    super.dispose();
  }

  Set<T> get _selectedValues => widget.value.map((v) => v.value).toSet();

  List<AppAutocompleteOption<T>> get _filtered {
    final lower = _query.toLowerCase();
    return widget.options.where((o) {
      if (_selectedValues.contains(o.value)) return false;
      return o.label.toLowerCase().contains(lower) ||
          (o.meta?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) _popoverController.show();
  }

  void _toggle(AppAutocompleteOption<T> item) {
    if (item.disabled) return;
    final exists = _selectedValues.contains(item.value);
    final next = exists
        ? widget.value.where((v) => v.value != item.value).toList()
        : [...widget.value, item];
    widget.onChanged?.call(next);
    _queryController.clear();
    _focusNode.requestFocus();
  }

  void _remove(T value) {
    widget.onChanged?.call(
      widget.value.where((v) => v.value != value).toList(),
    );
  }

  void _selectAll() {
    final all = widget.options.where((o) => !o.disabled).toList();
    widget.onChanged?.call(all);
    _popoverController.hide();
  }

  @override
  Widget build(BuildContext context) {
    final minHeight = widget.size.height;

    return AppPopover(
      controller: _popoverController,
      matchAnchorWidth: true,
      placement: AppPopoverPlacement.bottomStart,
      onOpenChange: (_) => setState(() {}),
      trigger: (context, show, hide, toggle) {
        return AppInputFrame(
          focusNode: _focusNode,
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          minHeight: minHeight,
          maxHeight: double.infinity,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s1 + AppSpacing.s0_5,
          ),
          child: AppPressable(
            onTap: widget.disabled ? null : () => _focusNode.requestFocus(),
            enabled: !widget.disabled,
            semanticLabel: widget.placeholder,
            mouseCursor: widget.disabled
                ? SystemMouseCursors.forbidden
                : SystemMouseCursors.text,
            child: Wrap(
              spacing: AppSpacing.s1,
              runSpacing: AppSpacing.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final item in widget.value)
                  AppChip(
                    removable: true,
                    disabled: widget.disabled,
                    size: widget.size == AppFieldSize.sm
                        ? AppChipSize.sm
                        : AppChipSize.md,
                    onRemove: () => _remove(item.value),
                    child: Text(item.label),
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 64),
                  child: TextField(
                    controller: _queryController,
                    focusNode: _focusNode,
                    enabled: !widget.disabled,
                    style: appBareInputTextStyle(
                      context,
                      size: widget.size,
                      disabled: widget.disabled,
                    ),
                    decoration: appBareInputDecoration(
                      context: context,
                      size: widget.size,
                      hintText: widget.value.isEmpty ? widget.placeholder : null,
                      disabled: widget.disabled,
                    ),
                    cursorColor: context.colors.borderFocus,
                    onTap: () => _popoverController.show(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      content: (context) {
        final filtered = _filtered;
        return AppPopoverListPanel(
          maxHeight: 240,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showSelectAll)
                AppPopoverListAction(
                  label: widget.allLabel,
                  onTap: _selectAll,
                ),
              if (filtered.isEmpty)
                const AppPopoverListMessage(message: 'No more options')
              else
                for (final item in filtered)
                  AppPopoverOptionRow(
                    label: item.label,
                    meta: item.meta,
                    disabled: item.disabled,
                    disabledReason: item.disabledReason,
                    selected: _selectedValues.contains(item.value),
                    onTap: item.disabled ? null : () => _toggle(item),
                  ),
            ],
          ),
        );
      },
    );
  }
}
