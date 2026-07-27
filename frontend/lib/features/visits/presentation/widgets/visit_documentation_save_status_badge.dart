import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/l10n/app_localizations_x.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_stale_conflict_dialog.dart';
import 'package:ai_clinic/l10n/app_localizations.dart';

/// Save-status chip for visit documentation with a stale-conflict resolution action.
class VisitDocumentationSaveStatusBadge extends ConsumerWidget {
  const VisitDocumentationSaveStatusBadge({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));
    final state = docAsync.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final style = _saveStatusStyle(state.saveStatus, l10n);
    if (style == null) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: AppSpacing.space2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppBadge(
          size: BadgeSize.sm,
          variant: BadgeVariant.soft,
          color: style.color,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 12),
              const SizedBox(width: AppSpacing.space1),
              Text(style.label),
            ],
          ),
        ),
        if (state.saveStatus == DocumentationSaveStatus.stale)
          AppButton(
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: () => _resolveStaleConflict(context, ref, state),
            child: Text(l10n.visitDocumentationResolveConflict),
          ),
      ],
    );
  }

  Future<void> _resolveStaleConflict(BuildContext context, WidgetRef ref, VisitDocumentationState state) async {
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final serverNote = _serverNoteFromState(state);
    final localNote = _localNoteFromState(state);
    final keepLocalDraft = await showVisitStaleConflictDialog(
      context,
      serverNote: serverNote,
      localNote: localNote,
    );
    if (!context.mounted || keepLocalDraft == null) {
      return;
    }

    await notifier.resolveStaleConflict(keepLocalDraft: keepLocalDraft);
  }
}

VisitClinicalNote _localNoteFromState(VisitDocumentationState state) {
  return VisitClinicalNote(
    complaint: state.complaint,
    history: state.history,
    examination: state.examination,
    diagnosis: state.diagnosis,
    plan: state.plan,
    updatedAt: state.expectedUpdatedAt,
  );
}

VisitClinicalNote _serverNoteFromState(VisitDocumentationState state) {
  return state.conflictingServerNote ?? state.persistedVisit.documentation ?? const VisitClinicalNote();
}

_SaveStatusStyle? _saveStatusStyle(DocumentationSaveStatus status, AppLocalizations l10n) {
  return switch (status) {
    DocumentationSaveStatus.idle => null,
    DocumentationSaveStatus.saving => _SaveStatusStyle(
      label: l10n.visitDocumentationSaveStatusSaving,
      color: BadgeColor.info,
      icon: Icons.sync,
    ),
    DocumentationSaveStatus.saved => _SaveStatusStyle(
      label: l10n.visitDocumentationSaveStatusSaved,
      color: BadgeColor.success,
      icon: Icons.check_circle_outline,
    ),
    DocumentationSaveStatus.stale => _SaveStatusStyle(
      label: l10n.visitDocumentationSaveStatusStale,
      color: BadgeColor.warning,
      icon: Icons.warning_amber_outlined,
    ),
    DocumentationSaveStatus.error => _SaveStatusStyle(
      label: l10n.visitDocumentationSaveStatusError,
      color: BadgeColor.danger,
      icon: Icons.error_outline,
    ),
  };
}

class _SaveStatusStyle {
  const _SaveStatusStyle({required this.label, required this.color, required this.icon});

  final String label;
  final BadgeColor color;
  final IconData icon;
}
