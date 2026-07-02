import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_joined_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_mode_toggle.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_shell.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_empty_sections_warning_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';

/// Visit documentation — clinical chart workspace (013).
class VisitDocumentationPage extends ConsumerWidget {
  const VisitDocumentationPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = visitId?.trim();
    if (id == null || id.isEmpty) {
      return const _VisitNotFound(message: 'Visit not found.');
    }

    final docAsync = ref.watch(visitDocumentationProvider(id));
    final auth = ref.watch(authSessionProvider);
    final canEditSoap = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return docAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit documentation…'),
      error: (error, _) => _VisitDocumentationError(
        message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
        onRetry: () => ref.invalidate(visitDocumentationProvider(id)),
        onBack: () => _goBack(context, id),
      ),
      data: (state) {
        final hasBranchAccess = auth.context?.branchIds.contains(state.visit.branchId) ?? false;
        final canEdit = canEditSoap && hasBranchAccess;
        final canSubmit = canEdit;

        return VisitPageShell(
          scrollBody: false,
          hideTopBar: true,
          onBack: () => _goBack(context, id),
          body: _VisitDocumentationBody(
            visitId: id,
            state: state,
            canEdit: canEdit,
            hasBranchAccess: hasBranchAccess,
            canSubmit: canSubmit,
            onBack: () => _goBack(context, id),
            onSubmit: () => _submitVisit(context, ref, id, state, canEdit: canEdit),
            onSaveAndClose: () => _saveAndClose(context, ref, id, canEdit: canEdit),
          ),
        );
      },
    );
  }

  static void _goBack(BuildContext context, String visitId) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.visitDetail(visitId));
  }

  Future<void> _submitVisit(
    BuildContext context,
    WidgetRef ref,
    String visitId,
    VisitDocumentationState state, {
    required bool canEdit,
  }) async {
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);

    try {
      // Sync Quill controllers and draft overlay into state before validating.
      // Validation must never run against stale editor content or trigger a save first.
      notifier.prepareEncounterReview();
      if (!context.mounted) return;

      final synced = ref.read(visitDocumentationProvider(visitId)).value;
      if (synced == null) return;

      final readiness = evaluateVisitSubmitReadiness(synced);

      if (!readiness.hasMinimumDocumentation) {
        AppToast.error(context, message: 'Enter at least one documentation field before submitting this visit.');
        return;
      }

      if (readiness.hasEmptySectionWarnings) {
        final continueToSubmit = await VisitEmptySectionsWarningDialog.show(
          context,
          emptyPhases: readiness.emptyPhases,
        );
        if (!continueToSubmit || !context.mounted) return;
      }

      if (canEdit && synced.needsPersistBeforeSubmit) {
        final saved = await notifier.saveAll();
        if (!context.mounted) return;
        if (!saved) {
          final latest = ref.read(visitDocumentationProvider(visitId)).value;
          AppToast.error(
            context,
            message: latest?.errorMessage ?? 'Unable to save changes before submitting. Fix any errors and try again.',
          );
          return;
        }
      }

      final latest = ref.read(visitDocumentationProvider(visitId)).value ?? synced;
      final result = await VisitSubmitDialog.show(
        context,
        visitId: visitId,
        expectedUpdatedAt: latest.expectedUpdatedAt,
      );

      if (result == null || !context.mounted) return;

      final appointmentId = state.visit.appointmentId.trim();
      if (appointmentId.isNotEmpty) {
        ref.invalidate(appointmentDetailProvider(appointmentId));
      }

      AppToast.success(context, message: 'Visit submitted. The linked appointment is now completed.');
    } catch (error) {
      if (!context.mounted) return;
      AppToast.error(
        context,
        message: error is RpcFailure ? visitMessageForRpc(error) : 'Unable to submit visit. Try again.',
      );
    }
  }

  Future<void> _saveAndClose(BuildContext context, WidgetRef ref, String visitId, {required bool canEdit}) async {
    final current = ref.read(visitDocumentationProvider(visitId)).value;
    if (current == null) return;

    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    var savedChanges = false;

    if (canEdit && current.hasUnsavedChanges) {
      final saved = await notifier.saveAll();
      if (!context.mounted) return;
      if (!saved) {
        final latest = ref.read(visitDocumentationProvider(visitId)).value;
        AppToast.error(
          context,
          message: latest?.errorMessage ?? 'Unable to save changes. Fix any errors and try again.',
        );
        return;
      }
      savedChanges = true;
    }

    if (!context.mounted) return;
    _goBack(context, visitId);
    if (savedChanges) {
      AppToast.success(context, message: 'Changes saved.');
    }
  }
}

class _VisitDocumentationBody extends ConsumerWidget {
  const _VisitDocumentationBody({
    required this.visitId,
    required this.state,
    required this.canEdit,
    required this.hasBranchAccess,
    required this.canSubmit,
    required this.onBack,
    required this.onSubmit,
    required this.onSaveAndClose,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool hasBranchAccess;
  final bool canSubmit;
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final VoidCallback onSaveAndClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;
    final canUploadAttachments = ref.watch(permissionServiceProvider).canUploadVisitAttachments();
    final status = visit.status;
    final activePhase = ref.watch(encounterActivePhaseProvider(visitId));
    final isOnSummary = activePhase == EncounterPhase.review;

    Widget? trailing;
    if (canSubmit && status == VisitStatus.inProgress) {
      final isSaving = state.saveStatus == DocumentationSaveStatus.saving;
      if (isOnSummary) {
        trailing = AppButton(
          key: const Key('visit_submit_button'),
          label: isSaving ? 'Saving…' : 'Submit visit',
          icon: const Icon(Icons.check_circle_outline, size: 18),
          isLoading: isSaving,
          onPressed: isSaving ? null : onSubmit,
        );
      } else {
        trailing = AppButton(
          key: const Key('visit_finish_button'),
          label: 'Finish Visit',
          icon: const Icon(Icons.summarize_outlined, size: 18),
          onPressed: () => ref.read(encounterActivePhaseProvider(visitId).notifier).setPhase(EncounterPhase.review),
        );
      }
    } else if (canSubmit && status == VisitStatus.completed) {
      trailing = AppButton(
        key: const Key('visit_save_close_button'),
        label: state.saveStatus == DocumentationSaveStatus.saving ? 'Saving…' : 'Save & close',
        variant: AppButtonVariant.outline,
        isLoading: state.saveStatus == DocumentationSaveStatus.saving,
        onPressed: state.saveStatus == DocumentationSaveStatus.saving ? null : onSaveAndClose,
      );
    }

    if (status == VisitStatus.completed) {
      final invoiceAction = VisitDetailActions(visitId: visitId, status: status, canEditDocumentation: false);
      trailing = trailing == null
          ? invoiceAction
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                invoiceAction,
                const SizedBox(width: SpacingTokens.sm),
                trailing,
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterJoinedHeader(
          visitId: visitId,
          visit: visit,
          onBack: onBack,
          beforeTrailing: const EncounterWorkspaceModeToggle(),
          trailing: trailing,
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        if (!hasBranchAccess) ...[
          const AppAlert(
            key: Key('visit_branch_access_denied_banner'),
            title: 'This visit belongs to a branch you are not assigned to.',
            subtitle: 'Clinical documentation is read-only.',
            icon: Icon(Icons.lock_outlined),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
        ],
        Expanded(
          child: EncounterWorkspaceShell(
            visitId: visitId,
            state: state,
            canEdit: canEdit,
            canUploadAttachments: canUploadAttachments,
            onRefresh: canEdit
                ? () {}
                : () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
          ),
        ),
      ],
    );
  }
}

class _VisitDocumentationError extends StatelessWidget {
  const _VisitDocumentationError({required this.message, required this.onRetry, required this.onBack});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return VisitPageShell(
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          AppAlert(title: message, variant: AppAlertVariant.destructive),
          const SizedBox(height: SpacingTokens.md),
          AppButton(label: 'Retry', onPressed: onRetry),
          const Spacer(),
        ],
      ),
    );
  }
}

class _VisitNotFound extends StatelessWidget {
  const _VisitNotFound({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message));
  }
}
