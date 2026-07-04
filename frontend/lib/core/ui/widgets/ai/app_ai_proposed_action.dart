import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

/// Lifecycle state for [AppAiProposedAction].
enum AppAiProposedActionState {
  /// Awaiting human review.
  proposed,

  /// User is editing structured fields.
  editing,

  /// Approval is being submitted.
  submitting,

  /// Action was approved and recorded.
  approved,

  /// User dismissed the proposal.
  rejected,

  /// Backend validation failed after approval attempt.
  failed,
}

/// Human-gated violet card for AI-proposed actions.
///
/// Presentational and fully controlled — the parent owns [state] and dispatches
/// [onApprove] through the normal validated backend path.
class AppAiProposedAction extends StatelessWidget {
  const AppAiProposedAction({
    required this.title,
    required this.summary,
    required this.state,
    this.fields,
    this.errorMessage,
    this.onApprove,
    this.onEdit,
    this.onDismiss,
    super.key,
  });

  final String title;
  final String summary;
  final AppAiProposedActionState state;
  final Widget? fields;
  final String? errorMessage;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onDismiss;

  bool get _showsFields =>
      fields != null &&
      (state == AppAiProposedActionState.proposed ||
          state == AppAiProposedActionState.editing ||
          state == AppAiProposedActionState.failed);

  bool get _showsActions =>
      state == AppAiProposedActionState.proposed ||
      state == AppAiProposedActionState.editing ||
      state == AppAiProposedActionState.failed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return AppSlideUp(
      child: AppCard(
        variant: AppCardVariant.ai,
        padding: AppCardPadding.md,
        child: AnimatedSwitcher(
          duration: AppMotion.resolvePreset(
            AppMotionPreset.fade,
            reduced: AppMotion.reduced(context),
          ).duration,
          child: Column(
            key: ValueKey<AppAiProposedActionState>(state),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        AppIcon(
                          icon: LucideIcons.sparkles,
                          size: AppIconSize.md,
                          color: colors.textAi,
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        Flexible(
                          child: Text(
                            'Proposed by AI',
                            style: typography.overline.copyWith(
                              color: colors.textAi,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(state: state),
                ],
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                title,
                style: typography.bodyStrong.copyWith(
                  color: colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                summary,
                style: typography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              if (_showsFields) ...[
                const SizedBox(height: AppSpacing.s4),
                AppFocusRing(
                  visible: state == AppAiProposedActionState.editing,
                  variant: AppFocusRingVariant.ai,
                  borderRadius: AppRadii.mdAll,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceDefault,
                      border: Border.all(color: colors.borderSubtle),
                      borderRadius: AppRadii.mdAll,
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
                      child: fields!,
                    ),
                  ),
                ),
              ],
              if (state == AppAiProposedActionState.failed &&
                  errorMessage != null) ...[
                const SizedBox(height: AppSpacing.s4),
                AppAlert(
                  variant: AppAlertVariant.danger,
                  title: errorMessage!,
                ),
              ],
              if (state == AppAiProposedActionState.submitting) ...[
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    const AppSpinner(size: AppSpinnerSize.sm),
                    const SizedBox(width: AppSpacing.s2),
                    Text(
                      'Submitting for approval…',
                      style: typography.bodySm.copyWith(color: colors.textAi),
                    ),
                  ],
                ),
              ],
              if (state == AppAiProposedActionState.approved) ...[
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Action recorded. Check the updated record in your workspace.',
                  style: typography.bodySm.copyWith(
                    color: colors.statusSuccessFg,
                  ),
                ),
              ],
              if (_showsActions) ...[
                const SizedBox(height: AppSpacing.s4),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: colors.borderSubtle),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: AppSpacing.s4,
                    ),
                    child: Wrap(
                      spacing: AppSpacing.s2,
                      runSpacing: AppSpacing.s2,
                      children: [
                        AppButton(
                          label: 'Approve',
                          variant: AppButtonVariant.ai,
                          size: AppButtonSize.sm,
                          leadingIcon: LucideIcons.check,
                          onPressed: onApprove,
                        ),
                        AppButton(
                          label: 'Edit',
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.sm,
                          leadingIcon: LucideIcons.pencil,
                          onPressed: onEdit,
                        ),
                        AppButton(
                          label: 'Dismiss',
                          variant: AppButtonVariant.ghost,
                          size: AppButtonSize.sm,
                          leadingIcon: LucideIcons.x,
                          onPressed: onDismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s4),
              Text(
                'AI never executes actions directly. Approve to run the validated backend path.',
                style: typography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.state});

  final AppAiProposedActionState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      AppAiProposedActionState.approved => const AppBadge(
        color: AppBadgeColor.success,
        variant: AppBadgeVariant.soft,
        label: 'Approved',
        size: AppBadgeSize.sm,
      ),
      AppAiProposedActionState.rejected => const AppBadge(
        color: AppBadgeColor.neutral,
        variant: AppBadgeVariant.soft,
        label: 'Dismissed',
        size: AppBadgeSize.sm,
      ),
      AppAiProposedActionState.failed => const AppBadge(
        color: AppBadgeColor.danger,
        variant: AppBadgeVariant.soft,
        label: 'Failed',
        size: AppBadgeSize.sm,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
