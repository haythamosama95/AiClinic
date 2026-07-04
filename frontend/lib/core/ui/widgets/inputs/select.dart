import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart'
    show AppDurations, AppMotion;
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Single option in [AppSelect].
class AppSelectOption {
  const AppSelectOption({
    required this.value,
    required this.label,
    this.disabled = false,
    this.disabledReason,
  });

  final String value;
  final String label;
  final bool disabled;
  final String? disabledReason;
}

/// Dropdown select with keyboard navigation and typeahead.
class AppSelect extends StatefulWidget {
  const AppSelect({
    super.key,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.placeholder = 'Select an option',
    this.value,
    this.options = const [],
    this.onValueChange,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final String placeholder;
  final String? value;
  final List<AppSelectOption> options;
  final ValueChanged<String>? onValueChange;

  @override
  State<AppSelect> createState() => _AppSelectState();
}

class _AppSelectState extends State<AppSelect> {
  bool _open = false;
  int _highlight = 0;
  String _typeahead = '';
  DateTime? _typeaheadReset;

  AppSelectOption? get _selected {
    for (final o in widget.options) {
      if (o.value == widget.value) return o;
    }
    return null;
  }

  void _select(String value) {
    widget.onValueChange?.call(value);
    setState(() => _open = false);
  }

  void _handleTypeahead(String char) {
    final now = DateTime.now();
    if (_typeaheadReset == null ||
        now.difference(_typeaheadReset!) > const Duration(milliseconds: 500)) {
      _typeahead = '';
    }
    _typeaheadReset = now;
    _typeahead += char.toLowerCase();
    final idx = widget.options.indexWhere(
      (o) => o.label.toLowerCase().startsWith(_typeahead),
    );
    if (idx >= 0) setState(() => _highlight = idx);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (widget.disabled || widget.readOnly) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _open = true;
        final delta = event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1;
        var next = _highlight + delta;
        if (next < 0) next = widget.options.length - 1;
        if (next >= widget.options.length) next = 0;
        _highlight = next;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _open) {
      final opt = widget.options[_highlight];
      if (!opt.disabled) _select(opt.value);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _open = false);
      return KeyEventResult.handled;
    }
    final label = event.character;
    if (label != null && label.isNotEmpty) {
      _handleTypeahead(label);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = _selected;
    final reducedMotion = AppMotion.isReducedMotion(context);

    return Focus(
      onKeyEvent: _handleKey,
      child: AppPopover(
        open: _open && !widget.disabled && !widget.readOnly,
        onOpenChange: (v) => setState(() => _open = v),
        matchTriggerWidth: true,
        contentPadding: const EdgeInsets.all(AppSpacing.s1),
        trigger: Semantics(
          button: true,
          identifier: widget.id,
          child: Container(
            constraints: BoxConstraints(
              minHeight: AppInputStyles.height(widget.size),
            ),
            padding: AppInputStyles.padding(widget.size),
            decoration: AppInputStyles.wrapperDecoration(
              context,
              size: widget.size,
              invalid: widget.invalid,
              disabled: widget.disabled,
              readOnly: widget.readOnly,
              focused: _open,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected?.label ?? widget.placeholder,
                    style: AppInputStyles.textStyle(context, widget.size)
                        .copyWith(
                          color: selected != null
                              ? colors.textPrimary
                              : colors.textPlaceholder,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: reducedMotion ? Duration.zero : AppDurations.fast,
                  child: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: colors.iconMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < widget.options.length; i++)
                _OptionTile(
                  option: widget.options[i],
                  selected: widget.options[i].value == widget.value,
                  highlighted: i == _highlight,
                  onTap: () {
                    if (!widget.options[i].disabled) {
                      _select(widget.options[i].value);
                    }
                  },
                  onHover: () => setState(() => _highlight = i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final AppSelectOption option;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Material(
      color: selected
          ? colors.surfaceSelected
          : highlighted
          ? colors.surfaceHover
          : Colors.transparent,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        onTap: option.disabled ? null : onTap,
        onHover: (_) => onHover(),
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: typography.body.copyWith(
                    color: option.disabled
                        ? colors.textDisabled
                        : colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected)
                Icon(Icons.check, size: 18, color: colors.actionPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
