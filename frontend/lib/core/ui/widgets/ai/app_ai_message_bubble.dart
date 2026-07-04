import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Speaker role for [AppAiMessageBubble].
enum AppAiMessageRole {
  /// End-aligned neutral bubble.
  user,

  /// Start-aligned AI surface with markdown content.
  assistant,
}

/// Chat bubble for user or assistant messages in AI surfaces.
class AppAiMessageBubble extends StatefulWidget {
  const AppAiMessageBubble({
    required this.role,
    required this.content,
    this.timestamp,
    this.onCopy,
    this.streaming = false,
    super.key,
  });

  final AppAiMessageRole role;
  final String content;
  final String? timestamp;
  final VoidCallback? onCopy;

  /// When true, content updates fade in (no per-character typewriter).
  final bool streaming;

  @override
  State<AppAiMessageBubble> createState() => _AppAiMessageBubbleState();
}

class _AppAiMessageBubbleState extends State<AppAiMessageBubble> {
  bool _hovering = false;

  bool get _isUser => widget.role == AppAiMessageRole.user;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final isUser = _isUser;

    return AppFade(
      child: Align(
        alignment: isUser
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxBubbleWidth = constraints.maxWidth * 0.85;
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: MouseRegion(
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isUser ? colors.surfaceMuted : colors.surfaceAi,
                  border: isUser
                      ? null
                      : Border.all(color: colors.borderAi),
                  borderRadius: AppRadii.lgAll,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isUser) ...[
                            Row(
                              children: [
                                AppIcon(
                                  icon: LucideIcons.sparkles,
                                  dimension: AppSpacing.s3,
                                  color: colors.textAi,
                                ),
                                const SizedBox(width: AppSpacing.s1 + AppSpacing.s0_5),
                                Flexible(
                                  child: Text(
                                    'AI assistant',
                                    style: typography.caption.copyWith(
                                      color: colors.textAi,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s2),
                          ],
                          _MessageBody(
                            role: widget.role,
                            content: widget.content,
                            streaming: widget.streaming,
                          ),
                          if (widget.timestamp != null) ...[
                            const SizedBox(height: AppSpacing.s2),
                            Text(
                              widget.timestamp!,
                              style: typography.caption.copyWith(
                                color: colors.textTertiary,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!isUser && widget.onCopy != null)
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: AnimatedOpacity(
                            duration: AppDurations.fast,
                            opacity: _hovering ? 1 : 0,
                            child: AppButton(
                              label: 'Copy',
                              variant: AppButtonVariant.ghost,
                              size: AppButtonSize.sm,
                              leadingIcon: LucideIcons.copy,
                              onPressed: widget.onCopy,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            );
          },
        ),
      ),
    );
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    required this.role,
    required this.content,
    required this.streaming,
  });

  final AppAiMessageRole role;
  final String content;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    if (role == AppAiMessageRole.user) {
      return Text(
        content,
        style: context.typography.body.copyWith(
          color: context.colors.textPrimary,
        ),
      );
    }

    final markdown = MarkdownWidget(
      data: content,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      selectable: true,
      config: aiAssistantMarkdownConfig(context),
    );

    if (!streaming) return markdown;

    return AnimatedSwitcher(
      duration: AppMotion.resolvePreset(
        AppMotionPreset.fade,
        reduced: AppMotion.reduced(context),
      ).duration,
      switchInCurve: AppMotion.resolvePreset(
        AppMotionPreset.fade,
        reduced: AppMotion.reduced(context),
      ).curve,
      child: KeyedSubtree(
        key: ValueKey<String>(content),
        child: markdown,
      ),
    );
  }
}

/// Markdown theme for assistant bubbles, mapped to design tokens.
MarkdownConfig aiAssistantMarkdownConfig(BuildContext context) {
  final colors = context.colors;
  final typography = context.typography;
  final primary = typography.body.copyWith(color: colors.textPrimary);

  return MarkdownConfig(configs: [
    PConfig(textStyle: primary),
    H1Config(
      style: typography.h1.copyWith(color: colors.textPrimary),
    ),
    H2Config(
      style: typography.h2.copyWith(color: colors.textPrimary),
    ),
    H3Config(
      style: typography.h3.copyWith(color: colors.textPrimary),
    ),
    H4Config(
      style: typography.bodyStrong.copyWith(color: colors.textPrimary),
    ),
    H5Config(
      style: typography.bodyStrong.copyWith(color: colors.textPrimary),
    ),
    H6Config(
      style: typography.bodyStrong.copyWith(color: colors.textPrimary),
    ),
    LinkConfig(
      style: typography.body.copyWith(
        color: colors.actionAi,
        decoration: TextDecoration.underline,
        decorationColor: colors.actionAi,
      ),
    ),
    CodeConfig(
      style: typography.bodySm.copyWith(
        color: colors.textPrimary,
        backgroundColor: colors.surfaceMuted,
      ),
    ),
    PreConfig(
      textStyle: typography.bodySm.copyWith(color: colors.textPrimary),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadii.mdAll,
        border: Border.all(color: colors.borderSubtle),
      ),
      padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
      margin: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.s2),
    ),
    BlockquoteConfig(
      sideColor: colors.borderAi,
      textColor: colors.textSecondary,
      padding: const EdgeInsets.only(
        left: AppSpacing.s4,
        top: AppSpacing.s0_5,
        bottom: AppSpacing.s0_5,
      ),
    ),
    HrConfig(
      color: colors.borderSubtle,
    ),
    ListConfig(
      marginLeft: AppSpacing.s4,
      marginBottom: AppSpacing.s2,
    ),
  ]);
}
