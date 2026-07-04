import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/theme_context_extensions.dart';

/// Toggles between standard and AI-assisted shell mode.
class AiModeToggle extends StatefulWidget {
  const AiModeToggle({
    super.key,
    required this.aiMode,
    required this.onToggle,
    this.showLabel = true,
  });

  final bool aiMode;
  final VoidCallback onToggle;
  final bool showLabel;

  @override
  State<AiModeToggle> createState() => _AiModeToggleState();
}

class _AiModeToggleState extends State<AiModeToggle> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final aiMode = widget.aiMode;

    final background = aiMode
        ? colors.surfaceAi
        : _hovered && !_pressed
        ? colors.surfaceHover
        : colors.surfaceDefault;
    final foreground = aiMode ? colors.textAi : colors.textPrimary;
    final borderColor = aiMode ? colors.borderAi : colors.borderDefault;
    final iconColor = aiMode ? colors.textAi : colors.iconDefault;
    final focusRing = aiMode ? colors.focusRingAi : colors.focusRing;

    return Semantics(
      button: true,
      toggled: aiMode,
      label: aiMode ? 'Switch to standard mode' : 'Switch to AI mode',
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space)) {
            widget.onToggle();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onToggle,
            child: AnimatedContainer(
              duration: AppDurations.base,
              curve: AppCurves.standard,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3,
                vertical: AppSpacing.s1 + AppSpacing.s0_5,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: _focused ? focusRing : borderColor,
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: iconColor),
                  if (widget.showLabel) ...[
                    const SizedBox(width: AppSpacing.s2),
                    Text(
                      aiMode ? 'AI mode' : 'Standard',
                      style: typography.bodyStrong.copyWith(color: foreground),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
