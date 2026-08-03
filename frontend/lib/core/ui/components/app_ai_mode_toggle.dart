import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/components/app_pressable.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_color_primitives.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// AI / standard mode toggle (web `AiModeToggle`).
class AppAiModeToggle extends StatefulWidget {
  const AppAiModeToggle({
    super.key,
    this.value,
    this.initialValue = false,
    this.onChanged,
    this.showLabel = true,
    this.aiModeLabel = 'AI mode',
    this.standardLabel = 'Standard',
  });

  /// Controlled state. Omit for uncontrolled mode.
  final bool? value;
  final bool initialValue;
  final ValueChanged<bool>? onChanged;
  final bool showLabel;
  final String aiModeLabel;
  final String standardLabel;

  @override
  State<AppAiModeToggle> createState() => _AppAiModeToggleState();
}

class _AppAiModeToggleState extends State<AppAiModeToggle> {
  late bool _internalValue;
  var _hovered = false;
  var _focused = false;

  bool get _isControlled => widget.value != null;

  bool get _effectiveValue => widget.value ?? _internalValue;

  bool get _canToggle => !_isControlled || widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _internalValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant AppAiModeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isControlled && widget.initialValue != oldWidget.initialValue) {
      _internalValue = widget.initialValue;
    }
  }

  void _toggle() {
    if (!_canToggle) return;

    final next = !_effectiveValue;
    if (!_isControlled) {
      setState(() => _internalValue = next);
    }
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiMode = _effectiveValue;

    final background = aiMode
        ? colors.surfaceAi
        : (_hovered ? colors.surfaceHover : colors.surfaceDefault);
    final borderColor = aiMode ? colors.borderAi : colors.borderDefault;
    final foreground = aiMode ? colors.textAi : colors.textPrimary;
    final iconColor = aiMode ? colors.textAi : colors.iconDefault;
    final focusRingColor = aiMode
        ? (isDark ? AppColorPrimitives.focusRingAiDark : AppColorPrimitives.focusRingAiLight)
        : (isDark ? AppColorPrimitives.focusRingDark : AppColorPrimitives.focusRingLight);

    final buttonBody = AnimatedContainer(
      duration: AppMotion.instant,
      curve: AppMotion.standardCurve,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.space3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor),
        boxShadow: _focused && _canToggle
            ? [BoxShadow(color: focusRingColor, blurRadius: 0, spreadRadius: 2)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 16, color: iconColor),
          if (widget.showLabel) ...[
            const SizedBox(width: AppSpacing.space2),
            Text(
              aiMode ? widget.aiModeLabel : widget.standardLabel,
              style: AppTypography.bodyStrong(context).copyWith(color: foreground),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      toggled: aiMode,
      enabled: _canToggle,
      label: aiMode ? 'Switch to standard mode' : 'Switch to AI mode',
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        canRequestFocus: _canToggle,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent || !_canToggle) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.space || event.logicalKey == LogicalKeyboardKey.enter) {
            _toggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onEnter: _canToggle ? (_) => setState(() => _hovered = true) : null,
          onExit: _canToggle ? (_) => setState(() => _hovered = false) : null,
          cursor: _canToggle ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: AppPressable(
            enabled: _canToggle,
            onPressed: _canToggle ? _toggle : null,
            child: buttonBody,
          ),
        ),
      ),
    );
  }
}
