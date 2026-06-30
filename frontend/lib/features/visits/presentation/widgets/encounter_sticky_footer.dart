import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';

/// Sticky save status and phase navigation footer (014 US4 / FR-017).
class EncounterStickyFooter extends ConsumerWidget {
  const EncounterStickyFooter({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.activePhase,
    required this.onPhaseSelected,
    super.key,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final EncounterPhase activePhase;
  final ValueChanged<EncounterPhase> onPhaseSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.visitTheme;
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final isSaving = state.saveStatus == DocumentationSaveStatus.saving;
    final previous = activePhase.previous;
    final next = activePhase.next;

    return DecoratedBox(
      key: const Key('encounter_sticky_footer'),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(top: BorderSide(color: theme.hairlineSoft)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.sm),
        child: Row(
          children: [
            _SaveStatus(state: state),
            const Spacer(),
            if (previous != null)
              AppButton(
                key: const Key('encounter_footer_prev'),
                label: 'Previous',
                variant: AppButtonVariant.outline,
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: isSaving ? null : () => onPhaseSelected(previous),
              ),
            if (previous != null && next != null) const SizedBox(width: SpacingTokens.sm),
            if (next != null)
              AppButton(
                key: const Key('encounter_footer_next'),
                label: 'Next',
                variant: AppButtonVariant.outline,
                onPressed: isSaving ? null : () => onPhaseSelected(next),
              ),
            if (canEdit) ...[
              const SizedBox(width: SpacingTokens.sm),
              AppButton(
                key: const Key('encounter_footer_save'),
                label: isSaving ? 'Saving…' : 'Save',
                icon: const Icon(Icons.save_outlined, size: 18),
                isLoading: isSaving,
                onPressed: isSaving ? null : () => notifier.save(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.state});

  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context) {
    final theme = context.visitTheme;

    return switch (state.saveStatus) {
      DocumentationSaveStatus.saving => Row(
        key: const Key('encounter_footer_status_saving'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: theme.pulseDeep)),
          const SizedBox(width: SpacingTokens.xs),
          Text('Saving…', style: theme.caption(color: theme.mutedInk)),
        ],
      ),
      DocumentationSaveStatus.saved => Row(
        key: const Key('encounter_footer_status_saved'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: theme.pulseDeep),
          const SizedBox(width: SpacingTokens.xs),
          Text('Saved', style: theme.bodyStrong(color: theme.pulseDeep, size: 13)),
        ],
      ),
      DocumentationSaveStatus.stale => Row(
        key: const Key('encounter_footer_status_stale'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_outlined, size: 15, color: theme.danger),
          const SizedBox(width: SpacingTokens.xs),
          Flexible(
            child: Text(
              state.errorMessage ?? 'Updated elsewhere — reload and save again.',
              style: theme.caption(color: theme.danger),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      DocumentationSaveStatus.error => Row(
        key: const Key('encounter_footer_status_error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 15, color: theme.danger),
          const SizedBox(width: SpacingTokens.xs),
          Flexible(
            child: Text(
              state.errorMessage ?? 'Could not save.',
              style: theme.caption(color: theme.danger),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      DocumentationSaveStatus.idle =>
        state.hasUnsavedDraft
            ? Row(
                key: const Key('encounter_footer_status_unsaved'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_outlined, size: 15, color: theme.mutedInk),
                  const SizedBox(width: SpacingTokens.xs),
                  Text('Unsaved changes', style: theme.caption(color: theme.mutedInk)),
                ],
              )
            : Row(
                key: const Key('encounter_footer_status_idle'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_done_outlined, size: 15, color: theme.mutedInk.withValues(alpha: 0.7)),
                  const SizedBox(width: SpacingTokens.xs),
                  Text('Up to date', style: theme.caption(color: theme.mutedInk)),
                ],
              ),
    };
  }
}
