import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_spinner.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_input_frame.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_popover_inputs_shared.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';

/// Result row for [AppAutocomplete].
class AppAutocompleteOption<T> {
  const AppAutocompleteOption({
    required this.value,
    required this.label,
    this.meta,
    this.avatarUrl,
    this.initials,
    this.disabled = false,
    this.disabledReason,
  });

  final T value;
  final String label;
  final String? meta;
  final String? avatarUrl;
  final String? initials;
  final bool disabled;
  final String? disabledReason;
}

/// Async combobox with debounced search and match highlighting.
class AppAutocomplete<T> extends StatefulWidget {
  const AppAutocomplete({
    this.onSearch,
    this.options,
    this.value,
    this.onSelected,
    this.onChanged,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.placeholder = 'Search…',
    this.debounceMs = 300,
    this.allowCreate = false,
    this.createLabel,
    this.onCreate,
    this.controller,
    this.focusNode,
    super.key,
  }) : assert(
         onSearch != null || options != null,
         'Provide onSearch or options',
       );

  /// Async search callback; receives the current query string.
  final Future<List<AppAutocompleteOption<T>>> Function(String query)? onSearch;

  /// Static options filtered locally when [onSearch] is null.
  final List<AppAutocompleteOption<T>>? options;

  final AppAutocompleteOption<T>? value;
  final ValueChanged<AppAutocompleteOption<T>?>? onSelected;
  final ValueChanged<AppAutocompleteOption<T>?>? onChanged;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final String placeholder;
  final int debounceMs;
  final bool allowCreate;
  final String Function(String query)? createLabel;
  final ValueChanged<String>? onCreate;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<AppAutocomplete<T>> createState() => _AppAutocompleteState<T>();
}

class _AppAutocompleteState<T> extends State<AppAutocomplete<T>> {
  late AppPopoverController _popoverController;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  List<AppAutocompleteOption<T>> _items = [];
  bool _loading = false;
  int _highlight = 0;
  String _query = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _popoverController = AppPopoverController();
    _items = widget.options ?? [];
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController(
        text: widget.value?.label ?? '',
      );
      _ownsController = true;
    }
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
    _controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant AppAutocomplete<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != null) {
      _controller.text = widget.value!.label;
    }
    if (widget.options != oldWidget.options && widget.onSearch == null) {
      _items = widget.options ?? [];
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_handleFocusChange);
    _controller.removeListener(_handleTextChange);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    _popoverController.dispose();
    super.dispose();
  }

  List<AppAutocompleteOption<T>> get _selectable =>
      _items.where((i) => !i.disabled).toList();

  void _handleFocusChange() {
    if (_focusNode.hasFocus) _popoverController.show();
  }

  void _handleTextChange() {
    final text = _controller.text;
    if (widget.value != null && text != widget.value!.label) {
      _notifyChange(null);
    }
    setState(() => _query = text);
    _scheduleSearch();
  }

  void _scheduleSearch() {
    if (!_popoverController.isOpen) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: widget.debounceMs), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _query;
    if (widget.onSearch != null) {
      setState(() => _loading = true);
      try {
        final results = await widget.onSearch!(q);
        if (!mounted || q != _query) return;
        setState(() {
          _items = results;
          _highlight = 0;
          _loading = false;
        });
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      final lower = q.toLowerCase();
      final filtered = (widget.options ?? []).where((item) {
        return item.label.toLowerCase().contains(lower) ||
            (item.meta?.toLowerCase().contains(lower) ?? false);
      }).toList();
      setState(() {
        _items = filtered;
        _highlight = 0;
      });
    }
  }

  void _notifyChange(AppAutocompleteOption<T>? next) {
    widget.onSelected?.call(next);
    widget.onChanged?.call(next);
  }

  void _select(AppAutocompleteOption<T> item) {
    if (item.disabled) return;
    _controller.text = item.label;
    _notifyChange(item);
    setState(() => _query = '');
    _popoverController.hide();
  }

  void _clearSelection() {
    _controller.clear();
    _notifyChange(null);
    setState(() => _query = '');
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (widget.disabled || event is! KeyDownEvent) return KeyEventResult.ignored;

    final selectable = _selectable;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _popoverController.show();
      setState(() {
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
    if (event.logicalKey == LogicalKeyboardKey.enter && _popoverController.isOpen) {
      if (selectable.isNotEmpty) {
        _select(selectable[_highlight]);
      } else if (widget.allowCreate && _query.isNotEmpty) {
        widget.onCreate?.call(_query);
        _popoverController.hide();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _popoverController.hide();
      _controller.text = widget.value?.label ?? '';
      setState(() => _query = '');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _showCreate =>
      widget.allowCreate &&
      _query.isNotEmpty &&
      !_items.any((i) => i.label.toLowerCase() == _query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final hasValue = widget.value != null;

    return AppPopover(
      controller: _popoverController,
      matchAnchorWidth: true,
      placement: AppPopoverPlacement.bottomStart,
      onOpenChange: (open) {
        if (open) _runSearch();
        setState(() {});
      },
      trigger: (context, show, hide, toggle) {
        return Focus(
          onKeyEvent: _handleKey,
          child: AppInputFrame(
            focusNode: _focusNode,
            size: widget.size,
            invalid: widget.invalid,
            disabled: widget.disabled,
            trailing: _buildTrailing(),
            child: TextField(
              controller: _controller,
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
                hintText: hasValue ? null : widget.placeholder,
                disabled: widget.disabled,
              ),
              cursorColor: context.colors.borderFocus,
              onTap: () => _popoverController.show(),
            ),
          ),
        );
      },
      content: (context) {
        final style = typography.bodyStrong.copyWith(
          color: context.colors.textPrimary,
        );

        if (_loading && _items.isEmpty) {
          return const AppPopoverListMessage(
            message: 'Searching…',
            semanticLive: true,
          );
        }

        if (!_loading && _items.isEmpty && _query.isNotEmpty) {
          return AppPopoverListMessage(
            message: 'No matches for "$_query"',
            semanticLive: true,
          );
        }

        return AppPopoverListPanel(
          maxHeight: 288,
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in _items)
                Builder(
                  builder: (context) {
                    final selectableIdx = _selectable.indexOf(item);
                    return AppPopoverOptionRow(
                      label: item.label,
                      meta: item.meta,
                      avatarUrl: item.avatarUrl,
                      initials: item.initials,
                      disabled: item.disabled,
                      disabledReason: item.disabledReason,
                      highlighted: selectableIdx == _highlight && !item.disabled,
                      selected: widget.value?.value == item.value,
                      labelWidget: AppHighlightMatch(
                        text: item.label,
                        query: _query,
                        style: style,
                      ),
                      onTap: item.disabled ? null : () => _select(item),
                    );
                  },
                ),
              if (_showCreate)
                _CreateRow(
                  label: widget.createLabel?.call(_query) ?? 'Create "$_query"',
                  onTap: () {
                    widget.onCreate?.call(_query);
                    _popoverController.hide();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget? _buildTrailing() {
    if (_loading) {
      return const AppSpinner(size: AppSpinnerSize.sm);
    }
    if (widget.value != null) {
      return AppPressable(
        onTap: _clearSelection,
        semanticLabel: 'Clear selection',
        child: Text(
          'Clear',
          style: context.typography.caption.copyWith(
            color: context.colors.textLink,
          ),
        ),
      );
    }
    return null;
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: AppPressable.builder(
        onTap: onTap,
        borderRadius: AppRadii.mdAll,
        semanticLabel: label,
        builder: (context, states, _) {
          final hovered = states.contains(WidgetState.hovered);
          return AnimatedContainer(
            duration: AppDurations.instant,
            color: hovered ? colors.surfaceHover : Colors.transparent,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s2,
            ),
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              style: typography.body.copyWith(color: colors.textLink),
            ),
          );
        },
      ),
    );
  }
}
