import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_popover.dart';
import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Item model for [AppCombobox] and [AppMultiSelect] (web `ComboboxItem`).
@immutable
class AppComboboxItem {
  const AppComboboxItem({
    required this.id,
    required this.label,
    this.meta,
    this.avatar,
    this.initials,
    this.disabled = false,
    this.disabledReason,
  });

  final String id;
  final String label;
  final String? meta;
  final String? avatar;
  final String? initials;
  final bool disabled;
  final String? disabledReason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppComboboxItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          meta == other.meta &&
          avatar == other.avatar &&
          initials == other.initials &&
          disabled == other.disabled &&
          disabledReason == other.disabledReason;

  @override
  int get hashCode => Object.hash(id, label, meta, avatar, initials, disabled, disabledReason);
}

/// Combobox / autocomplete control (web `Combobox`).
class AppCombobox extends StatefulWidget {
  const AppCombobox({
    this.id,
    this.size = AppInputSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder,
    this.value,
    this.onValueChange,
    this.onSearch,
    this.items,
    this.debounceMs = 300,
    this.allowCreate = false,
    this.createLabel,
    this.onCreate,
    super.key,
  });

  final String? id;
  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final String? placeholder;
  final AppComboboxItem? value;
  final ValueChanged<AppComboboxItem?>? onValueChange;
  final Future<List<AppComboboxItem>> Function(String query)? onSearch;
  final List<AppComboboxItem>? items;
  final int debounceMs;
  final bool allowCreate;
  final String Function(String query)? createLabel;
  final ValueChanged<String>? onCreate;

  @override
  State<AppCombobox> createState() => _AppComboboxState();
}

class _AppComboboxState extends State<AppCombobox> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();
  final _listKey = GlobalKey();

  var _open = false;
  var _loading = false;
  var _highlight = 0;
  List<AppComboboxItem> _items = [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _items = widget.items ?? [];
    if (widget.value != null) {
      _controller.text = widget.value!.label;
    }
    _focusNode
      ..addListener(_handleFocusChange)
      ..onKeyEvent = _handleKeyEvent;
    if (widget.onSearch != null && _open) {
      _runSearch(_controller.text);
    }
  }

  @override
  void didUpdateWidget(covariant AppCombobox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items && widget.items != null) {
      _items = widget.items!;
    }
    if (widget.value != oldWidget.value) {
      if (widget.value != null) {
        _controller.text = widget.value!.label;
      } else if (oldWidget.value != null) {
        _controller.clear();
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..onKeyEvent = null
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() => _open = true);
      _scheduleSearch(_controller.text);
    }
  }

  void _setOpen(bool open) {
    if (_open == open) return;
    setState(() => _open = open);
    if (open) {
      _scheduleSearch(_controller.text);
    }
  }

  void _scheduleSearch(String query) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: widget.debounceMs), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    if (!mounted) return;

    if (widget.onSearch != null) {
      setState(() => _loading = true);
      try {
        final results = await widget.onSearch!(query);
        if (!mounted) return;
        setState(() {
          _items = results;
          _highlight = 0;
        });
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } else if (widget.items != null) {
      final lower = query.toLowerCase();
      setState(() {
        _items = widget.items!
            .where(
              (item) => item.label.toLowerCase().contains(lower) || (item.meta?.toLowerCase().contains(lower) ?? false),
            )
            .toList();
        _highlight = 0;
      });
    }
  }

  List<AppComboboxItem> get _selectableItems => _items.where((item) => !item.disabled).toList();

  void _select(AppComboboxItem item) {
    if (item.disabled) return;
    widget.onValueChange?.call(item);
    _controller.text = item.label;
    setState(() {
      _open = false;
      _highlight = 0;
    });
  }

  void _clearSelection() {
    widget.onValueChange?.call(null);
    _controller.clear();
    setState(() => _highlight = 0);
    _scheduleSearch('');
  }

  void _handleChanged(String text) {
    if (widget.value != null) {
      widget.onValueChange?.call(null);
    }
    setState(() => _open = true);
    _scheduleSearch(text);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final selectable = _selectableItems;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() {
          _open = true;
          _highlight = (_highlight + 1).clamp(0, selectable.isEmpty ? 0 : selectable.length - 1);
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _highlight = (_highlight - 1).clamp(0, selectable.isEmpty ? 0 : selectable.length - 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        if (_open) {
          if (selectable.isNotEmpty && _highlight < selectable.length) {
            _select(selectable[_highlight]);
          } else if (_showCreate) {
            widget.onCreate?.call(_controller.text);
            setState(() => _open = false);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      case LogicalKeyboardKey.escape:
        setState(() {
          _open = false;
          if (widget.value == null) _controller.clear();
        });
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  bool get _showEmpty => !_loading && _items.isEmpty && _controller.text.isNotEmpty && widget.value == null;

  bool get _showCreate =>
      widget.allowCreate &&
      _controller.text.isNotEmpty &&
      !_items.any((item) => item.label.toLowerCase() == _controller.text.toLowerCase());

  String _createLabel(String query) => widget.createLabel?.call(query) ?? 'Create "$query"';

  @override
  Widget build(BuildContext context) {
    final metrics = appInputMetrics(context, widget.size);
    final colors = context.appColors;
    final hasValue = widget.value != null;

    final trailing = <Widget>[
      if (_loading)
        SizedBox(
          width: metrics.iconSize,
          height: metrics.iconSize,
          child: CircularProgressIndicator(strokeWidth: 2, color: colors.iconMuted),
        )
      else if (hasValue)
        AppPressable(
          onPressed: widget.disabled ? null : _clearSelection,
          child: Text('Clear', style: AppTypography.caption(context).copyWith(color: colors.textLink)),
        ),
    ];

    final field = TextField(
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
        hintText: hasValue ? null : (widget.placeholder ?? 'Search…'),
      ),
      onChanged: _handleChanged,
      onTap: () => _setOpen(true),
    );

    final listId = widget.id != null ? '${widget.id}-listbox' : null;

    final listbox = _ComboboxListbox(
      key: _listKey,
      listId: listId,
      loading: _loading,
      items: _items,
      query: _controller.text,
      highlight: _highlight,
      selectedId: widget.value?.id,
      showEmpty: _showEmpty,
      showCreate: _showCreate,
      createLabel: _createLabel(_controller.text),
      onHighlight: (index) => setState(() => _highlight = index),
      onSelect: _select,
      onCreate: () {
        widget.onCreate?.call(_controller.text);
        setState(() => _open = false);
      },
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
        triggerBuilder: (context, isOpen, onToggle) => _ComboboxInputShell(
          size: widget.size,
          invalid: widget.invalid,
          disabled: widget.disabled,
          focused: _focusNode.hasFocus,
          trailing: trailing,
          child: field,
        ),
      ),
    );
  }
}

class _ComboboxInputShell extends StatefulWidget {
  const _ComboboxInputShell({
    required this.size,
    required this.invalid,
    required this.disabled,
    required this.focused,
    required this.child,
    required this.trailing,
  });

  final AppInputSize size;
  final bool invalid;
  final bool disabled;
  final bool focused;
  final Widget child;
  final List<Widget> trailing;

  @override
  State<_ComboboxInputShell> createState() => _ComboboxInputShellState();
}

class _ComboboxInputShellState extends State<_ComboboxInputShell> {
  @override
  Widget build(BuildContext context) {
    final metrics = appInputMetrics(context, widget.size);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      height: metrics.height,
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      decoration: appInputDecoration(
        context,
        size: widget.size,
        invalid: widget.invalid,
        disabled: widget.disabled,
        focused: widget.focused,
      ),
      child: Row(
        children: [
          Expanded(child: appWrapMaterialInput(widget.child)),
          for (final item in widget.trailing) ...[SizedBox(width: metrics.gap), item],
        ],
      ),
    );
  }
}

class _ComboboxListbox extends StatelessWidget {
  const _ComboboxListbox({
    required this.loading,
    required this.items,
    required this.query,
    required this.highlight,
    required this.showEmpty,
    required this.showCreate,
    required this.createLabel,
    required this.onHighlight,
    required this.onSelect,
    required this.onCreate,
    this.listId,
    this.selectedId,
    super.key,
  });

  final String? listId;
  final bool loading;
  final List<AppComboboxItem> items;
  final String query;
  final int highlight;
  final String? selectedId;
  final bool showEmpty;
  final bool showCreate;
  final String createLabel;
  final ValueChanged<int> onHighlight;
  final ValueChanged<AppComboboxItem> onSelect;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selectable = items.where((item) => !item.disabled).toList();

    return Semantics(
      container: true,
      label: 'Suggestions',
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 288),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.space1),
          shrinkWrap: true,
          children: [
            if (loading && items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space6),
                child: Center(
                  child: Text('Searching…', style: AppTypography.bodySm(context).copyWith(color: colors.textTertiary)),
                ),
              ),
            if (showEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space6),
                child: Center(
                  child: Text(
                    'No matches for "$query"',
                    style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            for (final item in items)
              _ComboboxOption(
                item: item,
                query: query,
                highlighted: !item.disabled && selectable.indexOf(item) == highlight,
                selected: selectedId == item.id,
                onHover: () {
                  final index = selectable.indexOf(item);
                  if (index >= 0) onHighlight(index);
                },
                onSelect: () => onSelect(item),
              ),
            if (showCreate)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.borderSubtle)),
                ),
                child: AppPressable(
                  onPressed: onCreate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
                    child: Text(createLabel, style: AppTypography.body(context).copyWith(color: colors.textLink)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComboboxOption extends StatelessWidget {
  const _ComboboxOption({
    required this.item,
    required this.query,
    required this.highlighted,
    required this.selected,
    required this.onHover,
    required this.onSelect,
  });

  final AppComboboxItem item;
  final String query;
  final bool highlighted;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warningColor = isDark ? AppColorPrimitives.statusWarningFgDark : AppColorPrimitives.amber700;

    return Material(
      color: highlighted && !item.disabled ? colors.surfaceHover : Colors.transparent,
      child: InkWell(
        onTap: item.disabled ? null : onSelect,
        onHover: item.disabled ? null : (_) => onHover(),
        child: Opacity(
          opacity: item.disabled ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
            child: Row(
              children: [
                if (item.avatar != null || item.initials != null) ...[
                  _ComboboxAvatar(item: item),
                  const SizedBox(width: AppSpacing.space3),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HighlightedText(text: item.label, query: query, style: AppTypography.bodyStrong(context)),
                      if (item.meta != null)
                        Text(
                          item.meta!,
                          style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (item.disabled && item.disabledReason != null)
                        Text(
                          item.disabledReason!,
                          style: AppTypography.caption(context).copyWith(color: warningColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check, size: 16, color: colors.iconMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComboboxAvatar extends StatelessWidget {
  const _ComboboxAvatar({required this.item});

  final AppComboboxItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      width: 32,
      height: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceMuted, shape: BoxShape.circle),
        child: ClipOval(
          child: item.avatar != null
              ? Image.network(item.avatar!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initials(context))
              : _initials(context),
        ),
      ),
    );
  }

  Widget _initials(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Text(item.initials ?? '?', style: AppTypography.caption(context).copyWith(color: colors.textSecondary)),
    );
  }
}

/// Renders [text] with the query substring highlighted (web `<mark>`).
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.query, required this.style});

  final String text;
  final String query;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);
    if (index < 0) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    return Text.rich(
      TextSpan(
        style: style.copyWith(color: colors.textPrimary),
        children: [
          TextSpan(text: text.substring(0, index)),
          TextSpan(
            text: text.substring(index, index + query.length),
            style: style.copyWith(color: colors.textPrimary, backgroundColor: colors.surfaceSelected),
          ),
          TextSpan(text: text.substring(index + query.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
