import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/input_styles.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/spinner.dart';
import 'package:ai_clinic/core/ui/widgets/overlay/app_popover.dart';

/// Item in [AppCombobox] suggestion list.
class AppComboboxItem {
  const AppComboboxItem({
    required this.id,
    required this.label,
    this.meta,
    this.initials,
    this.disabled = false,
    this.disabledReason,
  });

  final String id;
  final String label;
  final String? meta;
  final String? initials;
  final bool disabled;
  final String? disabledReason;
}

/// Typeahead combobox with optional async search and create action.
class AppCombobox extends StatefulWidget {
  const AppCombobox({
    super.key,
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder = 'Search…',
    this.value,
    this.items,
    this.debounceMs = 300,
    this.allowCreate = false,
    this.createLabel,
    this.onValueChange,
    this.onSearch,
    this.onCreate,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final String placeholder;
  final AppComboboxItem? value;
  final List<AppComboboxItem>? items;
  final int debounceMs;
  final bool allowCreate;
  final String Function(String query)? createLabel;
  final ValueChanged<AppComboboxItem?>? onValueChange;
  final Future<List<AppComboboxItem>> Function(String query)? onSearch;
  final ValueChanged<String>? onCreate;

  @override
  State<AppCombobox> createState() => _AppComboboxState();
}

class _AppComboboxState extends State<AppCombobox> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _open = false;
  bool _focused = false;
  bool _loading = false;
  int _highlight = 0;
  List<AppComboboxItem> _items = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _items = widget.items ?? [];
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) setState(() => _open = true);
    });
    if (widget.value != null) {
      _controller.text = widget.value!.label;
    }
  }

  @override
  void didUpdateWidget(AppCombobox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value?.label ?? '';
    }
    if (widget.items != oldWidget.items && widget.onSearch == null) {
      _items = widget.items ?? [];
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<AppComboboxItem> get _selectable =>
      _items.where((i) => !i.disabled).toList();

  Future<void> _runSearch(String query) async {
    if (widget.onSearch != null) {
      setState(() => _loading = true);
      try {
        final results = await widget.onSearch!(query);
        if (mounted) setState(() => _items = results);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } else if (widget.items != null) {
      final lower = query.toLowerCase();
      setState(() {
        _items = widget.items!.where((item) {
          return item.label.toLowerCase().contains(lower) ||
              (item.meta?.toLowerCase().contains(lower) ?? false);
        }).toList();
      });
    }
  }

  void _scheduleSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: widget.debounceMs), () {
      _runSearch(query);
    });
  }

  void _select(AppComboboxItem item) {
    if (item.disabled) return;
    widget.onValueChange?.call(item);
    _controller.text = item.label;
    setState(() {
      _open = false;
      _highlight = 0;
    });
  }

  void _clear() {
    widget.onValueChange?.call(null);
    _controller.clear();
    _scheduleSearch('');
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final selectable = _selectable;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _open = true;
        _highlight = (_highlight + 1).clamp(0, selectable.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlight = (_highlight - 1).clamp(0, selectable.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _open) {
      if (selectable.isNotEmpty) {
        _select(selectable[_highlight]);
      } else if (widget.allowCreate && _controller.text.isNotEmpty) {
        widget.onCreate?.call(_controller.text);
        setState(() => _open = false);
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _open = false);
      _controller.text = widget.value?.label ?? '';
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final query = widget.value == null ? _controller.text : '';
    final showEmpty = !_loading && _items.isEmpty && query.isNotEmpty;
    final showCreate =
        widget.allowCreate &&
        query.isNotEmpty &&
        !_items.any((i) => i.label.toLowerCase() == query.toLowerCase());

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      onFocusChange: (f) => setState(() => _focused = f),
      child: AppPopover(
        open: _open && !widget.disabled,
        onOpenChange: (v) => setState(() => _open = v),
        matchTriggerWidth: true,
        contentPadding: EdgeInsets.zero,
        trigger: Container(
          constraints: BoxConstraints(
            minHeight: AppInputStyles.height(widget.size),
          ),
          padding: AppInputStyles.padding(widget.size),
          decoration: AppInputStyles.wrapperDecoration(
            context,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            focused: _focused || _open,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
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
                    hintText: widget.value == null ? widget.placeholder : null,
                    hintStyle: AppInputStyles.textStyle(
                      context,
                      widget.size,
                    ).copyWith(color: colors.textPlaceholder),
                  ),
                  onChanged: (value) {
                    if (widget.value != null) widget.onValueChange?.call(null);
                    setState(() => _open = true);
                    _scheduleSearch(value);
                  },
                  onTap: () => setState(() => _open = true),
                ),
              ),
              if (_loading)
                const AppSpinner(size: AppSpinnerSize.sm)
              else if (widget.value != null)
                TextButton(
                  onPressed: widget.disabled ? null : _clear,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s1,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Clear',
                    style: typography.caption.copyWith(color: colors.textLink),
                  ),
                ),
            ],
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 288),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
            children: [
              if (_loading && _items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  child: Center(
                    child: Text(
                      'Searching…',
                      style: typography.bodySm.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
              if (showEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  child: Center(
                    child: Text(
                      'No matches for "$query"',
                      style: typography.bodySm.copyWith(
                        color: colors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              for (final item in _items)
                _ComboboxItemTile(
                  item: item,
                  query: query,
                  highlighted: _selectable.indexOf(item) == _highlight,
                  selected: widget.value?.id == item.id,
                  onTap: () => _select(item),
                  onHover: () {
                    final idx = _selectable.indexOf(item);
                    if (idx >= 0) setState(() => _highlight = idx);
                  },
                ),
              if (showCreate)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      widget.onCreate?.call(query);
                      setState(() => _open = false);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: colors.borderSubtle),
                        ),
                      ),
                      child: Text(
                        widget.createLabel?.call(query) ?? 'Create "$query"',
                        style: typography.body.copyWith(color: colors.textLink),
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

class _ComboboxItemTile extends StatelessWidget {
  const _ComboboxItemTile({
    required this.item,
    required this.query,
    required this.highlighted,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  final AppComboboxItem item;
  final String query;
  final bool highlighted;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Material(
      color: highlighted && !item.disabled
          ? colors.surfaceHover
          : Colors.transparent,
      child: InkWell(
        onTap: item.disabled ? null : onTap,
        onHover: (_) => onHover(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s3,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: [
              if (item.initials != null) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: colors.surfaceMuted,
                  child: Text(
                    item.initials!,
                    style: typography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HighlightedText(
                      text: item.label,
                      query: query,
                      style: typography.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                      highlightColor: colors.surfaceSelected,
                    ),
                    if (item.meta != null)
                      Text(
                        item.meta!,
                        style: typography.caption.copyWith(
                          color: colors.textTertiary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (item.disabled && item.disabledReason != null)
                      Text(
                        item.disabledReason!,
                        style: typography.caption.copyWith(
                          color: colors.statusWarningFg,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
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

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.query,
    required this.style,
    required this.highlightColor,
  });

  final String text;
  final String query;
  final TextStyle style;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: style, overflow: TextOverflow.ellipsis);
    }
    final idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(text, style: style, overflow: TextOverflow.ellipsis);
    }
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, idx + query.length),
            style: style.copyWith(backgroundColor: highlightColor),
          ),
          TextSpan(text: text.substring(idx + query.length)),
        ],
      ),
    );
  }
}
