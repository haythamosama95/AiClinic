import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

/// Message author role for [AppAiMessageBubble].
enum AiMessageRole { user, assistant }

/// Chat message bubble for user and AI assistant turns (web `AiMessageBubble`).
class AppAiMessageBubble extends StatefulWidget {
  const AppAiMessageBubble({
    required this.role,
    required this.child,
    this.timestamp,
    this.onCopy,
    super.key,
  });

  final AiMessageRole role;
  final Widget child;
  final String? timestamp;
  final VoidCallback? onCopy;

  @override
  State<AppAiMessageBubble> createState() => _AppAiMessageBubbleState();
}

class _AppAiMessageBubbleState extends State<AppAiMessageBubble> {
  var _hovered = false;

  bool get _isUser => widget.role == AiMessageRole.user;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.85;

        return Row(
          mainAxisAlignment: _isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: _isUser ? _buildUserBubble(colors) : _buildAssistantBubble(colors),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserBubble(AppSemanticColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        child: _buildBubbleBody(colors),
      ),
    );
  }

  Widget _buildAssistantBubble(AppSemanticColors colors) {
    final showCopy = widget.onCopy != null;

    Widget bubble = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAi,
        border: Border.all(color: colors.borderAi),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: AppSpacing.space4,
          vertical: AppSpacing.space3,
        ),
        child: _buildBubbleBody(colors, assistantHeader: true),
      ),
    );

    if (showCopy) {
      bubble = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            bubble,
            PositionedDirectional(
              top: AppSpacing.space2,
              end: AppSpacing.space2,
              child: IgnorePointer(
                ignoring: !_hovered,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: AppMotion.instant,
                  curve: AppMotion.standardCurve,
                  child: AppButton(
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.sm,
                    onPressed: widget.onCopy,
                    leadingIcon: const Icon(Icons.copy, size: 14),
                    child: const Text('Copy'),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return bubble;
  }

  Widget _buildBubbleBody(AppSemanticColors colors, {bool assistantHeader = false}) {
    final bodyStyle = AppTypography.body(context).copyWith(color: colors.textPrimary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (assistantHeader) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 12, color: colors.textAi),
              const SizedBox(width: 6),
              Text(
                'AI assistant',
                style: AppTypography.caption(context).copyWith(color: colors.textAi),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),
        ],
        DefaultTextStyle(style: bodyStyle, child: widget.child),
        if (widget.timestamp != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            widget.timestamp!,
            style: AppTypography.caption(context).copyWith(
              color: colors.textTertiary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}
