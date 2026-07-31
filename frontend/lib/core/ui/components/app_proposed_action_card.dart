import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_card.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

enum ProposedActionState { proposed, editing, submitting, approved, rejected, failed }

/// Human-gated AI action card (web `ProposedActionCard`).
class AppProposedActionCard extends StatefulWidget {
  const AppProposedActionCard({
    required this.title,
    required this.summary,
    this.fields,
    this.state,
    this.errorMessage,
    this.onApprove,
    this.onEdit,
    this.onDismiss,
    super.key,
  });

  final String title;
  final String summary;
  final Widget? fields;
  final ProposedActionState? state;
  final String? errorMessage;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback? onDismiss;

  @override
  State<AppProposedActionCard> createState() => _AppProposedActionCardState();
}

class _AppProposedActionCardState extends State<AppProposedActionCard> {
  ProposedActionState _internalState = ProposedActionState.proposed;
  Timer? _submitTimer;

  ProposedActionState get _state => widget.state ?? _internalState;

  bool get _isControlled => widget.state != null;

  @override
  void dispose() {
    _submitTimer?.cancel();
    super.dispose();
  }

  void _handleApprove() {
    if (!_isControlled) {
      setState(() => _internalState = ProposedActionState.submitting);
      _submitTimer?.cancel();
      _submitTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted || _isControlled) return;
        setState(() => _internalState = ProposedActionState.approved);
      });
    }
    widget.onApprove?.call();
  }

  void _handleDismiss() {
    if (!_isControlled) {
      _submitTimer?.cancel();
      setState(() => _internalState = ProposedActionState.rejected);
    }
    widget.onDismiss?.call();
  }

  void _handleEdit() {
    if (!_isControlled) {
      setState(() => _internalState = ProposedActionState.editing);
    }
    widget.onEdit?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final state = _state;
    final showFields = widget.fields != null &&
        (state == ProposedActionState.proposed ||
            state == ProposedActionState.editing ||
            state == ProposedActionState.failed);
    final showActions = state == ProposedActionState.proposed ||
        state == ProposedActionState.editing ||
        state == ProposedActionState.failed;

    return AppCard(
      variant: CardVariant.ai,
      padding: CardPadding.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: colors.textAi),
                    const SizedBox(width: AppSpacing.space2),
                    Text(
                      'Proposed by AI',
                      style: AppTypography.overline(context).copyWith(color: colors.textAi),
                    ),
                  ],
                ),
              ),
              if (state == ProposedActionState.approved)
                const AppBadge(label: 'Approved', color: BadgeColor.success, variant: BadgeVariant.soft),
              if (state == ProposedActionState.rejected)
                const AppBadge(label: 'Dismissed', color: BadgeColor.neutral, variant: BadgeVariant.soft),
              if (state == ProposedActionState.failed)
                const AppBadge(label: 'Failed', color: BadgeColor.danger, variant: BadgeVariant.soft),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),
          Text(
            widget.title,
            style: AppTypography.bodyStrong(context).copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.space1),
          Text(
            widget.summary,
            style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
          ),
          if (showFields) ...[
            const SizedBox(height: AppSpacing.space4),
            _FieldsContainer(
              editing: state == ProposedActionState.editing,
              child: widget.fields!,
            ),
          ],
          if (state == ProposedActionState.failed && widget.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.space4),
            _FailedCallout(message: widget.errorMessage!),
          ],
          if (state == ProposedActionState.submitting) ...[
            const SizedBox(height: AppSpacing.space4),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.textAi),
                  ),
                ),
                const SizedBox(width: AppSpacing.space2),
                Text(
                  'Submitting for approval…',
                  style: AppTypography.bodySm(context).copyWith(color: colors.textAi),
                ),
              ],
            ),
          ],
          if (state == ProposedActionState.approved) ...[
            const SizedBox(height: AppSpacing.space4),
            Text(
              'Action recorded. Check the updated record in your workspace.',
              style: AppTypography.bodySm(context).copyWith(color: colors.statusSuccessFg),
            ),
          ],
          if (showActions) ...[
            const SizedBox(height: AppSpacing.space4),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.space4),
                child: Wrap(
                  spacing: AppSpacing.space2,
                  runSpacing: AppSpacing.space2,
                  children: [
                    AppButton(
                      variant: AppButtonVariant.ai,
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.check, size: 16),
                      onPressed: _handleApprove,
                      child: const Text('Approve'),
                    ),
                    AppButton(
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: _handleEdit,
                      child: const Text('Edit'),
                    ),
                    AppButton(
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.sm,
                      leadingIcon: const Icon(Icons.close, size: 16),
                      onPressed: _handleDismiss,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space4),
          Text(
            'AI never executes actions directly. Approve to run the validated backend path.',
            style: AppTypography.caption(context).copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _FieldsContainer extends StatelessWidget {
  const _FieldsContainer({required this.editing, required this.child});

  final bool editing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final focusRing = appInputFocusRingColor(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceDefault,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: editing ? [BoxShadow(color: focusRing, blurRadius: 0, spreadRadius: 2)] : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space4),
        child: child,
      ),
    );
  }
}

class _FailedCallout extends StatelessWidget {
  const _FailedCallout({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusDangerSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.statusDangerBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.cancel_outlined, size: 16, color: colors.statusDangerFg),
            ),
            const SizedBox(width: AppSpacing.space2),
            Expanded(
              child: Text(
                message,
                style: AppTypography.bodySm(context).copyWith(color: colors.statusDangerFg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
