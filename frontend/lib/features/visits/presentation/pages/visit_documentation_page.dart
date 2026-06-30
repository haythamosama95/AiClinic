import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';
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
          headerActions: [
            VisitDetailActions(visitId: id, status: state.visit.status, canEditDocumentation: canEdit),
            if (canSubmit && state.visit.status == VisitStatus.inProgress)
              AppButton(
                key: const Key('visit_submit_button'),
                label: 'Submit visit',
                icon: const Icon(Icons.check_circle_outline, size: 18),
                onPressed: () => _submitVisit(context, ref, id, state, canEdit: canEdit),
              )
            else if (canSubmit && state.visit.status == VisitStatus.completed)
              AppButton(
                key: const Key('visit_save_close_button'),
                label: state.saveStatus == DocumentationSaveStatus.saving ? 'Saving…' : 'Save & close',
                variant: AppButtonVariant.outline,
                isLoading: state.saveStatus == DocumentationSaveStatus.saving,
                onPressed: state.saveStatus == DocumentationSaveStatus.saving
                    ? null
                    : () => _saveAndClose(context, ref, id, canEdit: canEdit),
              ),
          ],
          onBack: () => _goBack(context, id),
          body: _VisitDocumentationBody(visitId: id, state: state, canEdit: canEdit, hasBranchAccess: hasBranchAccess),
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

    if (canEdit && state.hasUnsavedDraft) {
      await notifier.save();
      if (!context.mounted) return;
      final updated = ref.read(visitDocumentationProvider(visitId)).value;
      if (updated == null ||
          updated.saveStatus == DocumentationSaveStatus.error ||
          updated.saveStatus == DocumentationSaveStatus.stale) {
        return;
      }
    }

    final latest = ref.read(visitDocumentationProvider(visitId)).value ?? state;
    final result = await VisitSubmitDialog.show(context, visitId: visitId, expectedUpdatedAt: latest.expectedUpdatedAt);

    if (result == null || !context.mounted) return;

    AppToast.success(context, message: 'Visit submitted. The linked appointment is now completed.');
  }

  Future<void> _saveAndClose(BuildContext context, WidgetRef ref, String visitId, {required bool canEdit}) async {
    final current = ref.read(visitDocumentationProvider(visitId)).value;
    if (current == null) return;

    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    var savedChanges = false;

    if (canEdit && current.hasUnsavedDraft) {
      await notifier.save();
      if (!context.mounted) return;
      final updated = ref.read(visitDocumentationProvider(visitId)).value;
      if (updated == null ||
          updated.saveStatus == DocumentationSaveStatus.error ||
          updated.saveStatus == DocumentationSaveStatus.stale) {
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
  });

  final String visitId;
  final VisitDocumentationState state;
  final bool canEdit;
  final bool hasBranchAccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;
    final dateLabel = DateFormat('EEEE, MMM d, yyyy').format(visit.visitDate.toLocal());
    final canUploadAttachments = ref.watch(permissionServiceProvider).canUploadVisitAttachments();

    return VisitContentFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VisitHeroCard(
            dateLabel: dateLabel,
            doctorName: visit.doctorName,
            status: visit.status,
            vitalSigns: visit.vitalSigns,
          ),
          if (!hasBranchAccess) ...[
            const SizedBox(height: VisitPageTokens.sectionGap),
            const AppAlert(
              key: Key('visit_branch_access_denied_banner'),
              title: 'This visit belongs to a branch you are not assigned to.',
              subtitle: 'Clinical documentation is read-only.',
              icon: Icon(Icons.lock_outlined),
            ),
          ],
          const SizedBox(height: VisitPageTokens.sectionGap),
          VisitSectionCard(
            kind: VisitPanelKind.clinicalNote,
            title: 'Clinical note',
            description: 'Complaint, history, examination, diagnosis, and plan',
            child: ClinicalNoteEditor(visitId: visitId, state: state, canEdit: canEdit),
          ),
          const SizedBox(height: VisitPageTokens.sectionGap),
          VisitSectionGrid(
            children: [
              VisitSectionCard(
                kind: VisitPanelKind.vitalSigns,
                title: 'Vital signs',
                description: 'Record measurements from predefined options or custom entries',
                child: VitalSignList(
                  visitId: visitId,
                  vitalSigns: state.visit.vitalSigns,
                  predefinedVitalSigns: state.predefinedVitalSigns,
                  canEdit: canEdit,
                  onChanged: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
                ),
              ),
              VisitSectionCard(
                kind: VisitPanelKind.treatment,
                title: 'Treatment plans',
                description: 'Search medications, enter custom names, and record dose, frequency, and duration',
                child: TreatmentPlanList(
                  visitId: visitId,
                  treatmentPlans: state.visit.treatmentPlans,
                  canEdit: canEdit,
                  onChanged: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
                ),
              ),
              VisitSectionCard(
                kind: VisitPanelKind.investigation,
                title: 'Investigations',
                description: 'Search investigations catalog or enter custom names with optional notes',
                child: InvestigationList(
                  visitId: visitId,
                  investigations: state.visit.investigations,
                  canEdit: canEdit,
                  onChanged: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
                ),
              ),
              VisitSectionCard(
                kind: VisitPanelKind.attachment,
                title: 'Attachments',
                description: 'PDF, Word, JPEG, or PNG files up to 25 MB',
                child: VisitAttachmentList(
                  visitId: visitId,
                  branchId: visit.branchId,
                  attachments: state.visit.attachments,
                  canUpload: canUploadAttachments,
                  onChanged: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
                ),
              ),
            ],
          ),
        ],
      ),
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
