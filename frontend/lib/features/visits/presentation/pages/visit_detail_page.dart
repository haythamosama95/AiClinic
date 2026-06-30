import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/encounter_phase.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_documentation_layout.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_assessment.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_context.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_objective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_plan.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_phase_subjective.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Visit detail — clinical chart workspace with inline editing when permitted (013 US6).
class VisitDetailPage extends ConsumerWidget {
  const VisitDetailPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = visitId?.trim();
    if (id == null || id.isEmpty) {
      return const _VisitNotFound(message: 'Visit not found.');
    }

    final viewAsync = ref.watch(visitDetailViewProvider(id));

    return viewAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit…'),
      error: (error, _) => _VisitDetailError(
        message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
        onRetry: () => ref.invalidate(visitDetailViewProvider(id)),
        onBack: () => _goBack(context),
      ),
      data: (view) {
        if (view.canEditDocumentation) {
          return _EditableVisitDetailPage(visitId: id, view: view, onBack: () => _goBack(context));
        }
        return _ReadOnlyVisitDetailPage(view: view, onBack: () => _goBack(context));
      },
    );
  }

  static void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.patients);
  }
}

class _EditableVisitDetailPage extends ConsumerWidget {
  const _EditableVisitDetailPage({required this.visitId, required this.view, required this.onBack});

  final String visitId;
  final VisitDetailViewState view;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(visitDocumentationProvider(visitId));

    return docAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit…'),
      error: (error, _) => _VisitDetailError(
        message: error is RpcFailure ? visitMessageForRpc(error) : error.toString(),
        onRetry: () => ref.invalidate(visitDocumentationProvider(visitId)),
        onBack: onBack,
      ),
      data: (docState) => VisitPageShell(
        onBack: onBack,
        headerActions: [
          VisitDetailActions(visitId: visitId, status: docState.visit.status, canEditDocumentation: true),
        ],
        body: _VisitDetailBody(
          visitId: visitId,
          visit: docState.visit,
          canEdit: true,
          docState: docState,
          hasBranchAccess: view.hasBranchAccess,
          canUploadAttachments: view.canUploadAttachments,
          onRefresh: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
        ),
      ),
    );
  }
}

class _ReadOnlyVisitDetailPage extends StatelessWidget {
  const _ReadOnlyVisitDetailPage({required this.view, required this.onBack});

  final VisitDetailViewState view;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return VisitPageShell(
      onBack: onBack,
      headerActions: [
        VisitDetailActions(visitId: view.visit.id, status: view.visit.status, canEditDocumentation: false),
      ],
      body: _VisitDetailBody(
        visitId: view.visit.id,
        visit: view.visit,
        canEdit: false,
        hasBranchAccess: view.hasBranchAccess,
        canUploadAttachments: false,
        onRefresh: () {},
      ),
    );
  }
}

class _VisitDetailBody extends ConsumerWidget {
  const _VisitDetailBody({
    required this.visitId,
    required this.visit,
    required this.canEdit,
    required this.hasBranchAccess,
    required this.canUploadAttachments,
    required this.onRefresh,
    this.docState,
  });

  final String visitId;
  final VisitDetail visit;
  final bool canEdit;
  final bool hasBranchAccess;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;
  final VisitDocumentationState? docState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = visit.documentation;

    return Column(
      key: const Key('visit_detail_body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterHeader(visit: visit),
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
        EncounterDocumentationLayout(
          phases: [
            EncounterPhaseReadGroup(
              phase: EncounterPhase.context,
              child: EncounterPhaseContext(visit: visit),
            ),
            EncounterPhaseReadGroup(
              phase: EncounterPhase.subjective,
              child: EncounterPhaseSubjectiveDetail(visitId: visitId, state: docState, canEdit: canEdit, note: note),
            ),
            EncounterPhaseReadGroup(
              phase: EncounterPhase.objective,
              child: EncounterPhaseObjectiveDetail(
                visitId: visitId,
                visit: visit,
                canEdit: canEdit,
                docState: docState,
                onRefresh: onRefresh,
              ),
            ),
            EncounterPhaseReadGroup(
              phase: EncounterPhase.assessment,
              child: canEdit && docState != null
                  ? EncounterPhaseAssessmentReadOnly(visitId: visitId, state: docState!, canEdit: true)
                  : EncounterPhaseAssessmentFromVisit(note: note),
            ),
            EncounterPhaseReadGroup(
              phase: EncounterPhase.plan,
              initiallyExpanded: true,
              child: canEdit && docState != null
                  ? EncounterPhasePlan(
                      visitId: visitId,
                      state: docState!,
                      canEdit: true,
                      canUploadAttachments: canUploadAttachments,
                      onRefresh: onRefresh,
                    )
                  : _PlanReadOnly(
                      visit: visit,
                      visitId: visitId,
                      canUploadAttachments: canUploadAttachments,
                      onRefresh: onRefresh,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlanReadOnly extends StatelessWidget {
  const _PlanReadOnly({
    required this.visit,
    required this.visitId,
    required this.canUploadAttachments,
    required this.onRefresh,
  });

  final VisitDetail visit;
  final String visitId;
  final bool canUploadAttachments;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VisitSectionCard(
          kind: VisitPanelKind.clinicalNote,
          title: 'Plan',
          child: VisitDetailField(label: 'Plan', value: visit.documentation?.plan ?? '', abbr: 'P'),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitSectionCard(
          kind: VisitPanelKind.treatment,
          title: 'Treatment plans',
          child: _TreatmentPlansReadOnly(treatmentPlans: visit.treatmentPlans),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitSectionCard(
          kind: VisitPanelKind.investigation,
          title: 'Investigations',
          child: _InvestigationsReadOnly(investigations: visit.investigations),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitAttachmentList(
          visitId: visitId,
          branchId: visit.branchId,
          attachments: visit.attachments,
          canUpload: canUploadAttachments,
          onChanged: onRefresh,
          sectionKind: VisitPanelKind.attachment,
          sectionTitle: 'Attachments',
        ),
      ],
    );
  }
}

class _TreatmentPlansReadOnly extends StatelessWidget {
  const _TreatmentPlansReadOnly({required this.treatmentPlans});

  final List<TreatmentPlanItem> treatmentPlans;

  @override
  Widget build(BuildContext context) {
    if (treatmentPlans.isEmpty) {
      return const VisitEmptyHint(
        key: Key('visit_detail_treatment_plans_empty'),
        message: 'No treatment plans recorded.',
        icon: Icons.medication_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final plan in treatmentPlans)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: TreatmentPlanCardView(plan: plan),
          ),
      ],
    );
  }
}

class _InvestigationsReadOnly extends StatelessWidget {
  const _InvestigationsReadOnly({required this.investigations});

  final List<VisitInvestigation> investigations;

  @override
  Widget build(BuildContext context) {
    if (investigations.isEmpty) {
      return const VisitEmptyHint(
        key: Key('visit_detail_investigations_empty'),
        message: 'No investigations ordered.',
        icon: Icons.biotech_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final investigation in investigations)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: InvestigationCardView(investigation: investigation),
          ),
      ],
    );
  }
}

class _VisitDetailError extends StatelessWidget {
  const _VisitDetailError({required this.message, required this.onRetry, required this.onBack});

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
