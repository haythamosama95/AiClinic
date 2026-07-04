import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// AI interaction flow scaffold — entry, converse, propose, approve.
///
/// Composes AI entry slot → [AppAiPanel] converse → [AppAiProposedAction] →
/// Approve/Edit/Dismiss callbacks. Success toasts are caller-driven; failure
/// maps to the same [errorAlert] surfaces as forms.
class AiFlowPattern extends StatelessWidget {
  const AiFlowPattern({
    this.entry,
    this.headerTitle = 'AI assistant',
    this.headerDescription =
        'Proposals require your approval before anything is saved.',
    this.conversation,
    this.aiPanel,
    this.proposedAction,
    this.inputBar,
    this.footer,
    this.errorAlert,
    this.showAiHeader = true,
    super.key,
  });

  /// Slot for AI mode toggle or command entry (caller supplies widget).
  final Widget? entry;
  final String headerTitle;
  final String? headerDescription;
  final Widget? conversation;
  final Widget? aiPanel;
  final Widget? proposedAction;
  final Widget? inputBar;
  final Widget? footer;
  final Widget? errorAlert;
  final bool showAiHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entry != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
            child: entry!,
          ),
        ],
        if (showAiHeader)
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceAi,
              border: Border(
                bottom: BorderSide(color: colors.borderAi),
              ),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcon(
                        icon: LucideIcons.sparkles,
                        size: AppIconSize.sm,
                        color: colors.textAi,
                      ),
                      const SizedBox(width: AppSpacing.s2),
                      Expanded(
                        child: Text(
                          headerTitle,
                          style: typography.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (headerDescription != null) ...[
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      headerDescription!,
                      style: typography.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (errorAlert != null) ...[
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
            child: errorAlert!,
          ),
        ],
        Expanded(
          child: AppScrollArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?conversation,
                  if (aiPanel != null) ...[
                    if (conversation != null)
                      const SizedBox(height: AppSpacing.s4),
                    aiPanel!,
                  ],
                  if (proposedAction != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    proposedAction!,
                  ],
                ],
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colors.borderSubtle),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: footer ?? inputBar ?? const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
