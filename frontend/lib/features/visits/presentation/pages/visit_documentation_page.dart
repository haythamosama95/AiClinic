import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/auth/auth_route_guard.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/ui.dart';
import 'package:ai_clinic/features/appointments/presentation/providers/appointment_detail_provider.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/domain/visit_submit_readiness.dart';
import 'package:ai_clinic/features/visits/presentation/providers/encounter_step_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/utils/visit_presentation_formatting.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_ai_pane.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_context_pane.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_content.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_workspace_mode_toggle.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_empty_sections_warning_dialog.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';

/// Visit documentation — clinical encounter workspace (013 / 014).
class VisitDocumentationPage extends ConsumerStatefulWidget {
  const VisitDocumentationPage({
    required this.visitId,
    this.startEditing = false,
    super.key,
  });

  final String visitId;
  final bool startEditing;

  @override
  ConsumerState<VisitDocumentationPage> createState() => _VisitDocumentationPageState();
}

class _VisitDocumentationPageState extends ConsumerState<VisitDocumentationPage> {
  var _appliedStartEditing = false;
  var _aiPaneOpen = true;
  var _compactPane = WorkspacePane.primary;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authSessionProvider);
    if (!AuthRouteGuard.canAccessVisitDocumentation(auth)) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.noAccess,
        title: 'Visit documentation',
        description: 'You do not have permission to document visits.',
      );
    }

    final visitId = widget.visitId.trim();
    if (visitId.isEmpty) {
      return const AppEmptyState(
        variant: AppEmptyStateVariant.error,
        title: 'Visit not found',
        description: 'A valid visit id is required.',
      );
    }

    final docAsync = ref.watch(visitDocumentationProvider(visitId));
    final canEditSoap = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return docAsync.when(
      loading: () => const Center(child: AppSpinner()),
      error: (error, _) => AppErrorState(
        message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
        onRetry: () => ref.invalidate(visitDocumentationProvider(visitId)),
      ),
      data: (state) {
        final hasBranchAccess = auth.context?.branchIds.contains(state.visit.branchId) ?? false;
        final hasEditPermission = canEditSoap && hasBranchAccess;
        final canEditWorkspace = state.canEditWorkspace(hasEditPermission);
        final canSubmit = hasEditPermission;
        final canUploadAttachments =
            ref.watch(permissionServiceProvider).canUploadVisitAttachments() && hasBranchAccess;

        if (widget.startEditing &&
            !_appliedStartEditing &&
            hasEditPermission &&
            state.visit.status == VisitStatus.completed &&
            !canEditWorkspace) {
          _appliedStartEditing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(visitDocumentationProvider(visitId).notifier).enterWorkspaceEditMode();
          });
        }

        final title = 'Encounter · ${state.visit.doctorName}';

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_handleBack(canEdit: canEditWorkspace, visitId: visitId));
          },
          child: WorkspacePattern(
            title: title,
            aiPaneOpen: _aiPaneOpen,
            onAiPaneToggle: () => setState(() => _aiPaneOpen = !_aiPaneOpen),
            selectedPane: _compactPane,
            onPaneChanged: (pane) => setState(() => _compactPane = pane),
            headerActions: _HeaderActions(
              visitId: visitId,
              state: state,
              canEditWorkspace: canEditWorkspace,
              canSubmit: canSubmit,
              onSave: () => _saveAll(visitId),
              onSubmit: () => _submitVisit(visitId, state, canEdit: canEditWorkspace),
              onSaveAndClose: () => _saveAndClose(visitId, canEdit: canEditWorkspace),
              onEnterEditMode: () =>
                  ref.read(visitDocumentationProvider(visitId).notifier).enterWorkspaceEditMode(),
            ),
            contextPane: EncounterContextPane(visitId: visitId, state: state),
            primaryPane: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasBranchAccess) ...[
                  const Padding(
                    padding: EdgeInsetsDirectional.all(AppSpacing.s3),
                    child: AppAlert(
                      variant: AppAlertVariant.warning,
                      title: 'This visit belongs to a branch you are not assigned to.',
                      body: 'Clinical documentation is read-only.',
                    ),
                  ),
                ],
                Expanded(
                  child: EncounterWorkspaceContent(
                    visitId: visitId,
                    state: state,
                    canEdit: canEditWorkspace,
                    canUploadAttachments: canUploadAttachments,
                  ),
                ),
              ],
            ),
            aiPane: EncounterAiPane(visitId: visitId),
          ),
        );
      },
    );
  }

  Future<void> _handleBack({required bool canEdit, required String visitId}) async {
    final current = ref.read(visitDocumentationProvider(visitId)).value;
    if (canEdit && current != null && current.hasUnsavedChanges) {
      final discard = await showAppConfirmationDialog(
        context,
        title: 'Discard changes?',
        message: 'You have unsaved documentation. Leave without saving?',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!discard || !mounted) return;
    }
    _goBack(visitId);
  }

  void _goBack(String visitId) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.visitDetail(visitId));
  }

  Future<void> _saveAll(String visitId) async {
    final saved = await ref.read(visitDocumentationProvider(visitId).notifier).saveAll();
    if (!mounted) return;
    if (saved) {
      ref.showAppToast(message: 'Documentation saved.', variant: AppToastVariant.success);
    } else {
      final latest = ref.read(visitDocumentationProvider(visitId)).value;
      ref.showAppToast(
        message: latest?.errorMessage ?? 'Unable to save documentation.',
        variant: AppToastVariant.danger,
      );
    }
  }

  Future<void> _saveAndClose(String visitId, {required bool canEdit}) async {
    final current = ref.read(visitDocumentationProvider(visitId)).value;
    if (current == null) return;

    if (canEdit && current.hasUnsavedChanges) {
      final saved = await ref.read(visitDocumentationProvider(visitId).notifier).saveAll();
      if (!mounted) return;
      if (!saved) {
        final latest = ref.read(visitDocumentationProvider(visitId)).value;
        ref.showAppToast(
          message: latest?.errorMessage ?? 'Unable to save changes.',
          variant: AppToastVariant.danger,
        );
        return;
      }
    }

    if (!mounted) return;
    _goBack(visitId);
    ref.showAppToast(message: 'Changes saved.', variant: AppToastVariant.success);
  }

  Future<void> _submitVisit(
    String visitId,
    VisitDocumentationState state, {
    required bool canEdit,
  }) async {
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);

    try {
      notifier.prepareEncounterReview();
      if (!mounted) return;

      final synced = ref.read(visitDocumentationProvider(visitId)).value;
      if (synced == null) return;

      final readiness = evaluateVisitSubmitReadiness(synced);

      if (!readiness.hasMinimumDocumentation) {
        ref.showAppToast(
          message: 'Enter at least one documentation field before submitting this visit.',
          variant: AppToastVariant.danger,
        );
        return;
      }

      if (readiness.hasEmptySectionWarnings) {
        final continueToSubmit = await VisitEmptySectionsWarningDialog.show(
          context,
          emptyPhases: readiness.emptyPhases,
        );
        if (!continueToSubmit || !mounted) return;
      }

      if (canEdit && synced.needsPersistBeforeSubmit) {
        final saved = await notifier.saveAll();
        if (!mounted) return;
        if (!saved) {
          final latest = ref.read(visitDocumentationProvider(visitId)).value;
          ref.showAppToast(
            message: latest?.errorMessage ??
                'Unable to save changes before submitting. Fix any errors and try again.',
            variant: AppToastVariant.danger,
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

      if (result == null || !mounted) return;

      final appointmentId = state.visit.appointmentId.trim();
      if (appointmentId.isNotEmpty) {
        ref.invalidate(appointmentDetailProvider(appointmentId));
      }

      ref.showAppToast(
        message: 'Visit submitted. The linked appointment is now completed.',
        variant: AppToastVariant.success,
      );
    } on RpcFailure catch (error) {
      if (!mounted) return;
      ref.showAppToast(message: visitMessageForRpc(error), variant: AppToastVariant.danger);
    } catch (error) {
      if (!mounted) return;
      ref.showAppToast(message: 'Unable to submit visit. Try again.', variant: AppToastVariant.danger);
    }
  }
}

class _HeaderActions extends ConsumerWidget {
  const _HeaderActions({
    required this.visitId,
    required this.state,
    required this.canEditWorkspace,
    required this.canSubmit,
    required this.onSave,
    required this.onSubmit,
    required this.onSaveAndClose,
    required this.onEnterEditMode,
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEditWorkspace;
  final bool canSubmit;
  final VoidCallback onSave;
  final VoidCallback onSubmit;
  final VoidCallback onSaveAndClose;
  final VoidCallback onEnterEditMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;
    final status = visit.status;
    final activePhase = ref.watch(encounterActivePhaseProvider(visitId));
    final isOnSummary = activePhase == EncounterPhase.review;
    final isSaving = state.saveStatus == DocumentationSaveStatus.saving;

    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const EncounterWorkspaceModeToggle(),
        AppBadge(
          color: status == VisitStatus.completed ? AppBadgeColor.success : AppBadgeColor.info,
          child: Text(VisitPresentationFormatting.statusLabel(status)),
        ),
        if (canEditWorkspace)
          AppButton(
            label: isSaving ? 'Saving…' : 'Save draft',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            loading: isSaving,
            onPressed: isSaving ? null : onSave,
          ),
        if (canSubmit && status == VisitStatus.inProgress)
          if (isOnSummary)
            AppButton(
              label: 'Submit visit',
              size: AppButtonSize.sm,
              loading: isSaving,
              leadingIcon: LucideIcons.checkCircle2,
              onPressed: isSaving ? null : onSubmit,
            )
          else
            AppButton(
              label: 'Finish visit',
              size: AppButtonSize.sm,
              leadingIcon: LucideIcons.fileText,
              onPressed: () => ref
                  .read(encounterActivePhaseProvider(visitId).notifier)
                  .setPhase(EncounterPhase.review),
            ),
        if (canSubmit && status == VisitStatus.completed && canEditWorkspace)
          AppButton(
            label: 'Save & close',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            loading: isSaving,
            onPressed: isSaving ? null : onSaveAndClose,
          ),
        if (canSubmit && status == VisitStatus.completed && !canEditWorkspace)
          AppButton(
            label: 'Edit visit',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            leadingIcon: LucideIcons.pencil,
            onPressed: onEnterEditMode,
          ),
      ],
    );
  }
}
