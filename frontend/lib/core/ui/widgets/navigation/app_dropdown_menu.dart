import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/display/app_kbd.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_popover.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_tooltip.dart';

/// Minimum width for dropdown menu panels (`10rem`).
const double kAppDropdownMenuMinWidth = AppSpacing.s10 * 4;

/// Logical alignment of a dropdown menu panel relative to its anchor.
enum AppDropdownMenuAlign {
  start,
  center,
  end,
}

/// Maps [AppDropdownMenuAlign] to an RTL-aware [AppPopoverPlacement].
AppPopoverPlacement appDropdownMenuAlignToPlacement(AppDropdownMenuAlign align) {
  return switch (align) {
    AppDropdownMenuAlign.start => AppPopoverPlacement.bottomStart,
    AppDropdownMenuAlign.center => AppPopoverPlacement.bottom,
    AppDropdownMenuAlign.end => AppPopoverPlacement.bottomEnd,
  };
}

/// Signature for an [AppDropdownMenu] trigger builder.
typedef AppDropdownMenuTriggerBuilder = Widget Function(
  BuildContext context,
  VoidCallback show,
  VoidCallback hide,
  VoidCallback toggle,
);

/// Anchored dropdown menu built on [AppPopover] with `motion-fade-scale`.
class AppDropdownMenu extends StatefulWidget {
  const AppDropdownMenu({
    required this.trigger,
    required this.children,
    this.controller,
    this.align = AppDropdownMenuAlign.start,
    this.minWidth = kAppDropdownMenuMinWidth,
    this.onOpenChange,
    super.key,
  });

  final AppPopoverController? controller;
  final AppDropdownMenuTriggerBuilder trigger;
  final List<Widget> children;
  final AppDropdownMenuAlign align;
  final double minWidth;
  final ValueChanged<bool>? onOpenChange;

  @override
  State<AppDropdownMenu> createState() => _AppDropdownMenuState();
}

class _AppDropdownMenuState extends State<AppDropdownMenu> {
  late AppPopoverController _controller;
  late bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppPopoverController();
  }

  @override
  void didUpdateWidget(covariant AppDropdownMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) {
        _controller.dispose();
      }
      _ownsController = widget.controller == null;
      _controller = widget.controller ?? AppPopoverController();
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPopover(
      controller: _controller,
      placement: appDropdownMenuAlignToPlacement(widget.align),
      onOpenChange: widget.onOpenChange,
      trigger: widget.trigger,
      content: (_) => AppDropdownMenuContent(
        minWidth: widget.minWidth,
        onClose: _controller.hide,
        children: widget.children,
      ),
    );
  }
}

/// Menu panel surface with padding, min width, and keyboard navigation.
class AppDropdownMenuContent extends StatefulWidget {
  const AppDropdownMenuContent({
    required this.children,
    this.minWidth = kAppDropdownMenuMinWidth,
    this.onClose,
    super.key,
  });

  final List<Widget> children;
  final double minWidth;
  final VoidCallback? onClose;

  @override
  State<AppDropdownMenuContent> createState() => _AppDropdownMenuContentState();
}

class _AppDropdownMenuContentState extends State<AppDropdownMenuContent> {
  final List<_RegisteredMenuItem> _items = [];
  int _nextItemOrder = 0;
  int _highlightedIndex = -1;
  String _typeaheadBuffer = '';
  Timer? _typeaheadReset;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _typeaheadReset?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _register(_RegisteredMenuItem item) {
    final existing = _items.indexWhere((e) => e.id == item.id);
    if (existing >= 0) {
      _items[existing] = item;
    } else {
      _items.add(item);
      _items.sort((a, b) => a.order.compareTo(b.order));
    }
  }

  void _unregister(Object id) {
    _items.removeWhere((e) => e.id == id);
    if (_highlightedIndex >= _items.length) {
      _highlightedIndex = _items.isEmpty ? -1 : _items.length - 1;
    }
  }

  List<_RegisteredMenuItem> get _enabledItems =>
      _items.where((item) => !item.disabled).toList();

  void _setHighlighted(int index) {
    if (_highlightedIndex == index) return;
    setState(() => _highlightedIndex = index);
  }

  void _activateHighlighted() {
    if (_highlightedIndex < 0 || _highlightedIndex >= _items.length) return;
    final item = _items[_highlightedIndex];
    if (item.disabled) return;
    item.onSelected();
    widget.onClose?.call();
  }

  void _moveHighlight(int delta) {
    final enabled = _enabledItems;
    if (enabled.isEmpty) return;

    final currentItem =
        _highlightedIndex >= 0 && _highlightedIndex < _items.length
            ? _items[_highlightedIndex]
            : null;
    var enabledIndex = currentItem == null
        ? -1
        : enabled.indexWhere((e) => e.id == currentItem.id);

    if (enabledIndex < 0) {
      enabledIndex = delta > 0 ? 0 : enabled.length - 1;
    } else {
      enabledIndex = (enabledIndex + delta) % enabled.length;
      if (enabledIndex < 0) enabledIndex += enabled.length;
    }

    final next = enabled[enabledIndex];
    final listIndex = _items.indexWhere((e) => e.id == next.id);
    _setHighlighted(listIndex);
  }

  void _handleTypeahead(String character) {
    _typeaheadReset?.cancel();
    _typeaheadBuffer += character.toLowerCase();

    final enabled = _enabledItems;
    _RegisteredMenuItem? match;
    for (final item in enabled) {
      if (item.label.toLowerCase().startsWith(_typeaheadBuffer)) {
        match = item;
        break;
      }
    }

    if (match != null) {
      final listIndex = _items.indexWhere((e) => e.id == match!.id);
      _setHighlighted(listIndex);
    }

    _typeaheadReset = Timer(AppDurations.base, () {
      _typeaheadBuffer = '';
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _activateHighlighted();
      return KeyEventResult.handled;
    }

    final label = event.character;
    if (label != null && label.isNotEmpty && label.trim().isNotEmpty) {
      final ch = label.trim();
      if (ch.length == 1 && RegExp(r'[\w]').hasMatch(ch)) {
        _handleTypeahead(ch);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return _AppDropdownMenuScope(
      register: _register,
      unregister: _unregister,
      allocateOrder: () => _nextItemOrder++,
      highlightedIndex: _highlightedIndex,
      items: _items,
      onClose: widget.onClose,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s1),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: widget.minWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section label (overline) inside a dropdown menu.
class AppDropdownMenuLabel extends StatelessWidget {
  const AppDropdownMenuLabel({
    required this.label,
    super.key,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.s2,
        AppSpacing.s1 + AppSpacing.s0_5,
        AppSpacing.s2,
        AppSpacing.s1 + AppSpacing.s0_5,
      ),
      child: Text(
        label,
        style: context.typography.overline.copyWith(
          color: context.colors.textTertiary,
        ),
      ),
    );
  }
}

/// Horizontal separator between dropdown menu items.
class AppDropdownMenuSeparator extends StatelessWidget {
  const AppDropdownMenuSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
      child: SizedBox(
        height: AppSpacing.sPx,
        width: double.infinity,
        child: ColoredBox(color: context.colors.borderSubtle),
      ),
    );
  }
}

/// Interactive row inside [AppDropdownMenuContent].
class AppDropdownMenuItem extends StatefulWidget {
  const AppDropdownMenuItem({
    required this.label,
    this.leading,
    this.shortcutKeys,
    this.checked = false,
    this.destructive = false,
    this.disabled = false,
    this.disabledReason,
    this.onSelected,
    this.order,
    super.key,
  });

  final String label;
  final IconData? leading;
  final List<String>? shortcutKeys;
  final bool checked;
  final bool destructive;
  final bool disabled;
  final String? disabledReason;
  final VoidCallback? onSelected;
  final int? order;

  @override
  State<AppDropdownMenuItem> createState() => _AppDropdownMenuItemState();
}

class _AppDropdownMenuItemState extends State<AppDropdownMenuItem> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRegistration();
  }

  @override
  void didUpdateWidget(covariant AppDropdownMenuItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRegistration();
  }

  @override
  void deactivate() {
    _AppDropdownMenuScope.maybeOf(context)?.unregister(widget.key ?? this);
    super.deactivate();
  }

  void _syncRegistration() {
    final scope = _AppDropdownMenuScope.maybeOf(context);
    if (scope == null) return;
    scope.register(
      _RegisteredMenuItem(
        id: widget.key ?? this,
        order: widget.order ?? scope.allocateOrder(),
        label: widget.label,
        disabled: widget.disabled,
        onSelected: _handleSelected,
      ),
    );
  }

  void _handleSelected() {
    if (widget.disabled) return;
    widget.onSelected?.call();
    _AppDropdownMenuScope.maybeOf(context)?.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _AppDropdownMenuScope.maybeOf(context);
    final items = scope?.items ?? const <_RegisteredMenuItem>[];
    final index = items.indexWhere((e) => e.id == (widget.key ?? this));
    final highlighted = scope != null && scope.highlightedIndex == index;

    Widget row = AppMenuItemTile(
      label: widget.label,
      leading: widget.leading,
      shortcutKeys: widget.shortcutKeys,
      checked: widget.checked,
      destructive: widget.destructive,
      disabled: widget.disabled,
      highlighted: highlighted,
      onPressed: widget.disabled ? null : _handleSelected,
    );

    if (widget.disabled && widget.disabledReason != null) {
      row = AppTooltip(
        message: widget.disabledReason!,
        child: row,
      );
    }

    return row;
  }
}

/// Shared menu row visuals — icon, label, shortcut or check trailing.
///
/// Used by [AppDropdownMenuItem] and [AppMenu] entry rendering to avoid
/// duplicating layout logic.
class AppMenuItemTile extends StatelessWidget {
  const AppMenuItemTile({
    required this.label,
    this.leading,
    this.shortcutKeys,
    this.checked = false,
    this.destructive = false,
    this.disabled = false,
    this.highlighted = false,
    this.onPressed,
    super.key,
  });

  final String label;
  final IconData? leading;
  final List<String>? shortcutKeys;
  final bool checked;
  final bool destructive;
  final bool disabled;
  final bool highlighted;
  final VoidCallback? onPressed;

  static const EdgeInsetsDirectional _padding = EdgeInsetsDirectional.fromSTEB(
    AppSpacing.s2,
    AppSpacing.s1 + AppSpacing.s0_5,
    AppSpacing.s2,
    AppSpacing.s1 + AppSpacing.s0_5,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final foreground = disabled
        ? colors.textDisabled
        : destructive
            ? colors.statusDangerFg
            : colors.textPrimary;

    final background = highlighted
        ? (destructive ? colors.statusDangerSurface : colors.surfaceHover)
        : Colors.transparent;

    return AppPressable.builder(
      enabled: !disabled && onPressed != null,
      onTap: onPressed,
      borderRadius: AppRadii.mdAll,
      mouseCursor:
          disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, states, _) {
        final pressed = states.contains(WidgetState.pressed);
        final hovered = states.contains(WidgetState.hovered);
        final interactiveBg = destructive
            ? colors.statusDangerSurface
            : colors.surfaceHover;
        final resolvedBg = pressed || hovered
            ? interactiveBg
            : background;

        return AnimatedContainer(
          duration: AppDurations.instant,
          curve: AppEasings.standard,
          padding: _padding,
          decoration: BoxDecoration(
            color: resolvedBg,
            borderRadius: AppRadii.mdAll,
          ),
          child: Row(
            children: [
              if (leading != null) ...[
                AppIcon(
                  icon: leading!,
                  size: AppIconSize.sm,
                  color: disabled ? colors.textDisabled : colors.iconDefault,
                ),
                const SizedBox(width: AppSpacing.s2),
              ],
              Expanded(
                child: Text(
                  label,
                  style: typography.body.copyWith(color: foreground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (checked)
                AppIcon(
                  icon: LucideIcons.check,
                  size: AppIconSize.sm,
                  color: colors.textLink,
                )
              else if (shortcutKeys != null && shortcutKeys!.isNotEmpty)
                AppKbd(keys: shortcutKeys),
            ],
          ),
        );
      },
    );
  }
}

class _RegisteredMenuItem {
  const _RegisteredMenuItem({
    required this.id,
    required this.order,
    required this.label,
    required this.disabled,
    required this.onSelected,
  });

  final Object id;
  final int order;
  final String label;
  final bool disabled;
  final VoidCallback onSelected;
}

class _AppDropdownMenuScope extends InheritedWidget {
  const _AppDropdownMenuScope({
    required this.register,
    required this.unregister,
    required this.allocateOrder,
    required this.highlightedIndex,
    required this.items,
    required this.onClose,
    required super.child,
  });

  final void Function(_RegisteredMenuItem item) register;
  final void Function(Object id) unregister;
  final int Function() allocateOrder;
  final int highlightedIndex;
  final List<_RegisteredMenuItem> items;
  final VoidCallback? onClose;

  static _AppDropdownMenuScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AppDropdownMenuScope>();
  }

  @override
  bool updateShouldNotify(_AppDropdownMenuScope oldWidget) {
    return highlightedIndex != oldWidget.highlightedIndex ||
        items != oldWidget.items ||
        onClose != oldWidget.onClose;
  }
}
