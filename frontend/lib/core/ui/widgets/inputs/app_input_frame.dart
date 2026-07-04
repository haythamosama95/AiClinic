import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_field_size.dart';

/// Visual state bundle for the shared input field frame.
@immutable
class AppInputFrameState {
  const AppInputFrameState({
    this.focused = false,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.hovered = false,
  });

  final bool focused;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final bool hovered;

  AppInputFrameState copyWith({bool? focused, bool? invalid, bool? disabled, bool? readOnly, bool? hovered}) {
    return AppInputFrameState(
      focused: focused ?? this.focused,
      invalid: invalid ?? this.invalid,
      disabled: disabled ?? this.disabled,
      readOnly: readOnly ?? this.readOnly,
      hovered: hovered ?? this.hovered,
    );
  }
}

/// Produces border, background, and focus-ring decoration for input fields.
@immutable
class _AppInputDecoration {
  const _AppInputDecoration({required this.state, this.minHeight, this.maxHeight, this.padding});

  final AppInputFrameState state;
  final double? minHeight;
  final double? maxHeight;
  final EdgeInsetsDirectional? padding;

  static const double _ringWidth = AppSignal.thickness;

  Color _background(AppColors colors) {
    if (state.disabled) return colors.actionDisabledBg;
    if (state.readOnly) return colors.surfaceSunken;
    return colors.surfaceDefault;
  }

  Color _borderColor(AppColors colors) {
    if (state.invalid) {
      return state.focused ? colors.statusDangerFg : colors.statusDangerBorder;
    }
    if (state.focused) return colors.borderFocus;
    return colors.borderDefault;
  }

  List<BoxShadow>? _focusRing(AppColors colors) {
    if (!state.focused) return null;
    final ringColor = state.invalid ? colors.statusDangerFg.withValues(alpha: 0.35) : colors.focusRing;
    return [BoxShadow(color: ringColor, blurRadius: 0, spreadRadius: _ringWidth)];
  }

  BoxDecoration resolve(BuildContext context) {
    final colors = context.colors;
    return BoxDecoration(
      color: _background(colors),
      borderRadius: AppRadii.mdAll,
      border: Border.all(color: _borderColor(colors)),
      boxShadow: _focusRing(colors),
    );
  }

  Duration transitionDuration(BuildContext context) {
    return AppMotion.reduced(context) ? AppDurations.instant : AppDurations.fast;
  }
}

/// Bordered container shared by all text-based inputs.
///
/// Composes leading/trailing slots around a borderless inner control so every
/// field shares identical sizing, borders, and focus treatment.
class AppInputFrame extends StatefulWidget {
  const AppInputFrame({
    required this.child,
    this.size = AppFieldSize.md,
    this.invalid = false,
    this.disabled = false,
    this.readOnly = false,
    this.focusNode,
    this.leading,
    this.trailing,
    this.minHeight,
    this.maxHeight,
    this.padding,
    this.gap = AppSpacing.s2,
    super.key,
  });

  final Widget child;
  final AppFieldSize size;
  final bool invalid;
  final bool disabled;
  final bool readOnly;
  final FocusNode? focusNode;
  final Widget? leading;
  final Widget? trailing;
  final double? minHeight;
  final double? maxHeight;
  final EdgeInsetsDirectional? padding;
  final double gap;

  @override
  State<AppInputFrame> createState() => _AppInputFrameState();
}

class _AppInputFrameState extends State<AppInputFrame> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _initFocusNode();
  }

  void _initFocusNode() {
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      _ownsFocusNode = false;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant AppInputFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _focusNode.removeListener(_handleFocusChange);
      if (_ownsFocusNode) {
        _focusNode.dispose();
      }
      _initFocusNode();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _focusNode.hasFocus;
    if (_focused != focused) {
      setState(() => _focused = focused);
    }
  }

  AppInputFrameState get _state => AppInputFrameState(
    focused: _focused,
    invalid: widget.invalid,
    disabled: widget.disabled,
    readOnly: widget.readOnly,
    hovered: _hovered,
  );

  @override
  Widget build(BuildContext context) {
    final decoration = _AppInputDecoration(
      state: _state,
      minHeight: widget.minHeight,
      maxHeight: widget.maxHeight,
      padding: widget.padding,
    );
    final resolvedPadding = widget.padding ?? widget.size.padding;
    final minHeight = widget.minHeight ?? widget.size.height;

    Widget frame = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.disabled
          ? SystemMouseCursors.forbidden
          : widget.readOnly
          ? SystemMouseCursors.basic
          : SystemMouseCursors.text,
      child: AnimatedContainer(
        duration: decoration.transitionDuration(context),
        curve: AppEasings.standard,
        constraints: BoxConstraints(minHeight: minHeight, maxHeight: widget.maxHeight ?? double.infinity),
        padding: resolvedPadding,
        decoration: decoration.resolve(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.leading != null) ...[widget.leading!, SizedBox(width: widget.gap)],
            Expanded(
              child: Material(type: MaterialType.transparency, color: Colors.transparent, child: widget.child),
            ),
            if (widget.trailing != null) ...[SizedBox(width: widget.gap), widget.trailing!],
          ],
        ),
      ),
    );

    if (widget.focusNode != null) {
      return frame;
    }

    return Focus(focusNode: _focusNode, skipTraversal: true, child: frame);
  }
}

/// Inline icon affordance used inside input frames (clear, reveal, etc.).
class AppInputInlineButton extends StatelessWidget {
  const AppInputInlineButton({required this.icon, required this.semanticLabel, this.onPressed, super.key});

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel,
      borderRadius: AppRadii.smAll,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s0_5),
        child: AppIcon(icon: icon, size: AppIconSize.sm, color: context.colors.iconMuted),
      ),
    );
  }
}

/// Larger stepper button used by [AppNumberField].
class AppInputStepperButton extends StatelessWidget {
  const AppInputStepperButton({required this.icon, required this.semanticLabel, this.onPressed, super.key});

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  static const double _dimension = AppSpacing.s8 - AppSpacing.s1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppPressable.builder(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel,
      borderRadius: AppRadii.smAll,
      builder: (context, states, _) {
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: AppDurations.instant,
          width: _dimension,
          height: _dimension,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? colors.surfaceHover : Colors.transparent,
            borderRadius: AppRadii.smAll,
          ),
          child: AppIcon(icon: icon, size: AppIconSize.sm, color: colors.iconDefault),
        );
      },
    );
  }
}

/// Shared text style for bare inputs inside [AppInputFrame].
TextStyle appBareInputTextStyle(
  BuildContext context, {
  required AppFieldSize size,
  bool disabled = false,
  bool readOnly = false,
}) {
  final colors = context.colors;
  final base = size.textStyle(context);
  final color = disabled ? colors.textDisabled : colors.textPrimary;

  return context.typography.tabular(base.copyWith(color: color, height: 1));
}

/// Builds a borderless [InputDecoration] for inner [TextField] widgets.
InputDecoration appBareInputDecoration({
  required BuildContext context,
  required AppFieldSize size,
  String? hintText,
  bool disabled = false,
  bool readOnly = false,
}) {
  final style = appBareInputTextStyle(context, size: size, disabled: disabled, readOnly: readOnly);

  return InputDecoration(
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    contentPadding: EdgeInsets.zero,
    hintText: hintText,
    hintStyle: style.copyWith(color: context.colors.textPlaceholder),
    filled: false,
  );
}

/// Prefix/suffix affix label inside an input frame.
class AppInputAffix extends StatelessWidget {
  const AppInputAffix({required this.label, required this.size, super.key});

  final String label;
  final AppFieldSize size;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: size.affixStyle(context));
  }
}

/// Muted leading/trailing icon slot.
class AppInputIconSlot extends StatelessWidget {
  const AppInputIconSlot({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppIcon(icon: icon, size: AppIconSize.sm, color: context.colors.iconMuted);
  }
}

/// Keyboard shortcut hint chip shown in search fields.
class AppInputShortcutHint extends StatelessWidget {
  const AppInputShortcutHint({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s1, vertical: AppSpacing.s0_5),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadii.smAll,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Text(label, style: typography.caption.copyWith(color: colors.textTertiary)),
    );
  }
}
