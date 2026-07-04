import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/interaction/app_focus_ring.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/tokens/app_durations.dart';
import 'package:ai_clinic/core/ui/tokens/app_easings.dart';
import 'package:ai_clinic/core/ui/widgets/overlays/app_tooltip.dart';

/// Builds [AppPressable] content with access to interaction [states].
typedef AppPressableBuilder = Widget Function(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
);

/// Canonical interactive wrapper for clickable design-system components.
class AppPressable extends StatefulWidget {
  /// Wraps [child] with default press scale and focus ring behavior.
  const AppPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius,
    this.mouseCursor = SystemMouseCursors.click,
    this.focusRingVariant = AppFocusRingVariant.standard,
    super.key,
  }) : builder = null;

  /// Exposes [states] to a custom builder while the wrapper handles focus,
  /// press scale, and semantics.
  const AppPressable.builder({
    required this.builder,
    this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.borderRadius,
    this.mouseCursor = SystemMouseCursors.click,
    this.focusRingVariant = AppFocusRingVariant.standard,
    super.key,
  });

  final Widget? child;
  final AppPressableBuilder? builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final String? semanticLabel;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;
  final BorderRadius? borderRadius;
  final MouseCursor mouseCursor;
  final AppFocusRingVariant focusRingVariant;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  late final WidgetStatesController _statesController;
  late final FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  bool get _isInteractive => widget.enabled && widget.onTap != null;

  @override
  void initState() {
    super.initState();
    _statesController = WidgetStatesController();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChange);
    _syncStates();
  }

  @override
  void didUpdateWidget(covariant AppPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      if (widget.focusNode != null) {
        _focusNode = widget.focusNode!;
        _ownsFocusNode = false;
      } else {
        _focusNode = FocusNode();
        _ownsFocusNode = true;
      }
      _focusNode.addListener(_handleFocusChange);
      _handleFocusChange();
    }
    if (widget.enabled != oldWidget.enabled ||
        widget.onTap != oldWidget.onTap) {
      if (!widget.enabled) {
        _pressed = false;
        _hovered = false;
      }
      _syncStates();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    _statesController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (_focused != focused) {
      setState(() => _focused = focused);
      _syncStates();
    }
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    _syncStates();
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    _syncStates();
  }

  void _syncStates() {
    _statesController.update(WidgetState.disabled, !widget.enabled);
    _statesController.update(WidgetState.pressed, _pressed && _isInteractive);
    _statesController.update(WidgetState.hovered, _hovered && _isInteractive);
    _statesController.update(WidgetState.focused, _focused && _isInteractive);
  }

  void _handleActivate() {
    if (_isInteractive) {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final scaleDuration = reduced ? AppDurations.instant : AppDurations.fast;
    final scale = (!_isInteractive || reduced || !_pressed) ? 1.0 : 0.98;

    Widget content = widget.builder != null
        ? widget.builder!(context, _statesController.value, widget.child)
        : widget.child ?? const SizedBox.shrink();

    content = AnimatedScale(
      scale: scale,
      duration: scaleDuration,
      curve: AppEasings.out,
      child: content,
    );

    content = AppFocusRing(
      visible: _focused && _isInteractive,
      variant: widget.focusRingVariant,
      borderRadius: widget.borderRadius,
      child: content,
    );

    content = Semantics(
      button: widget.onTap != null,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      onTap: _isInteractive ? widget.onTap : null,
      child: FocusableActionDetector(
        enabled: _isInteractive,
        autofocus: widget.autofocus,
        focusNode: _focusNode,
        onShowFocusHighlight: (value) {
          if (_focused != value) {
            setState(() => _focused = value);
            _syncStates();
          }
        },
        onShowHoverHighlight: _setHovered,
        mouseCursor: _isInteractive ? widget.mouseCursor : SystemMouseCursors.basic,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _handleActivate();
              return null;
            },
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _isInteractive ? (_) => _setPressed(true) : null,
          onPointerUp: _isInteractive ? (_) => _setPressed(false) : null,
          onPointerCancel: _isInteractive ? (_) => _setPressed(false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _isInteractive ? widget.onTap : null,
            onLongPress: _isInteractive ? widget.onLongPress : null,
            child: content,
          ),
        ),
      ),
    );

    if (!widget.enabled) {
      content = IgnorePointer(child: content);
    }

    if (widget.tooltip != null) {
      content = AppTooltip(message: widget.tooltip!, child: content);
    }

    return content;
  }
}
