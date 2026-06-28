import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
import 'package:ai_clinic/core/ui/theme/semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/application/visit_rpc_messages.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_investigation.dart';
import 'package:ai_clinic/features/visits/domain/visit_vital_sign.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/clinical_note_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Visit detail — scannable documentation layout with inline editing when permitted (013 US6).
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
      data: (docState) => _VisitDetailScaffold(
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
    return _VisitDetailScaffold(
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

class _VisitDetailScaffold extends StatelessWidget {
  const _VisitDetailScaffold({required this.onBack, required this.headerActions, required this.body});

  final VoidCallback onBack;
  final List<Widget> headerActions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Back', onPressed: onBack),
              const Spacer(),
              ...headerActions.map(
                (action) => Padding(
                  padding: const EdgeInsets.only(left: SpacingTokens.sm),
                  child: action,
                ),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Expanded(child: SingleChildScrollView(child: body)),
        ],
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

  static final _dateFormat = DateFormat('EEEE, MMM d, yyyy');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateLabel = _dateFormat.format(visit.visitDate.toLocal());

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          key: const Key('visit_detail_body'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VisitHeroCard(dateLabel: dateLabel, doctorName: visit.doctorName, status: visit.status),
            if (!hasBranchAccess) ...[
              const SizedBox(height: SpacingTokens.lg),
              const AppAlert(
                key: Key('visit_branch_access_denied_banner'),
                title: 'This visit belongs to a branch you are not assigned to.',
                subtitle: 'Clinical documentation is read-only.',
                icon: Icon(Icons.lock_outlined),
              ),
            ],
            const SizedBox(height: SpacingTokens.lg),
            VisitSectionCard(
              title: 'Clinical note',
              description: canEdit ? 'Complaint, history, examination, diagnosis, and plan' : null,
              child: KeyedSubtree(
                key: const Key('visit_detail_clinical_note_section'),
                child: canEdit && docState != null
                    ? ClinicalNoteEditor(visitId: visitId, state: docState!, canEdit: canEdit)
                    : _ClinicalNoteReadOnly(note: visit.documentation),
              ),
            ),
            const SizedBox(height: SpacingTokens.lg),
            VisitSectionCard(
              title: 'Vital signs',
              child: canEdit && docState != null
                  ? VitalSignList(
                      visitId: visitId,
                      vitalSigns: visit.vitalSigns,
                      predefinedVitalSigns: docState!.predefinedVitalSigns,
                      canEdit: canEdit,
                      onChanged: onRefresh,
                    )
                  : _VitalSignsReadOnly(vitalSigns: visit.vitalSigns),
            ),
            const SizedBox(height: SpacingTokens.lg),
            VisitSectionCard(
              title: 'Treatment plans',
              child: canEdit
                  ? TreatmentPlanList(
                      visitId: visitId,
                      treatmentPlans: visit.treatmentPlans,
                      canEdit: canEdit,
                      onChanged: onRefresh,
                    )
                  : _TreatmentPlansReadOnly(treatmentPlans: visit.treatmentPlans),
            ),
            const SizedBox(height: SpacingTokens.lg),
            VisitSectionCard(
              title: 'Investigations',
              child: canEdit
                  ? InvestigationList(
                      visitId: visitId,
                      investigations: visit.investigations,
                      canEdit: canEdit,
                      onChanged: onRefresh,
                    )
                  : _InvestigationsReadOnly(investigations: visit.investigations),
            ),
            const SizedBox(height: SpacingTokens.lg),
            VisitSectionCard(
              title: 'Attachments',
              child: VisitAttachmentList(
                visitId: visitId,
                branchId: visit.branchId,
                attachments: visit.attachments,
                canUpload: canUploadAttachments,
                onChanged: onRefresh,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClinicalNoteReadOnly extends StatelessWidget {
  const _ClinicalNoteReadOnly({required this.note});

  final VisitClinicalNote? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClinicalNoteSection(key: const Key('visit_detail_complaint'), label: 'Complaint', value: note?.complaint),
        _ClinicalNoteSection(key: const Key('visit_detail_history'), label: 'History', value: note?.history),
        _ClinicalNoteSection(
          key: const Key('visit_detail_examination'),
          label: 'Examination',
          value: note?.examination,
        ),
        _ClinicalNoteSection(key: const Key('visit_detail_diagnosis'), label: 'Diagnosis', value: note?.diagnosis),
        _ClinicalNoteSection(key: const Key('visit_detail_plan'), label: 'Plan', value: note?.plan),
      ],
    );
  }
}

class _ClinicalNoteSection extends StatelessWidget {
  const _ClinicalNoteSection({required this.label, required this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: label, value: value ?? '');
  }
}

class _VitalSignsReadOnly extends StatelessWidget {
  const _VitalSignsReadOnly({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    final colors = context.semanticColors;

    if (vitalSigns.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Text(
          'No vital signs recorded.',
          key: const Key('visit_detail_vital_signs_empty'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final sign in vitalSigns)
          Padding(
            padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
            child: VitalSignCardView(sign: sign),
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
    final colors = context.semanticColors;

    if (treatmentPlans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Text(
          'No treatment plans recorded.',
          key: const Key('visit_detail_treatment_plans_empty'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
        ),
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
    final colors = context.semanticColors;

    if (investigations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SpacingTokens.md),
        child: Text(
          'No investigations ordered.',
          key: const Key('visit_detail_investigations_empty'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.mutedForeground),
        ),
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
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppIconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Back', onPressed: onBack),
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
