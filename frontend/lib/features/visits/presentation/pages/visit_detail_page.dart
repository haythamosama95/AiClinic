import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/core/rpc/rpc_result.dart';
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
import 'package:ai_clinic/features/visits/presentation/widgets/encounter_header.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/investigation_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/vital_sign_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_page_tokens.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_patient_info_card.dart';
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
    return Column(
      key: const Key('visit_detail_body'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EncounterHeader(visit: visit),
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitPatientBasicInfoCard(patientId: visit.patientId),
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
          description: canEdit ? 'Complaint, history, examination, diagnosis, and plan' : null,
          child: KeyedSubtree(
            key: const Key('visit_detail_clinical_note_section'),
            child: canEdit && docState != null
                ? ClinicalNoteEditor(visitId: visitId, state: docState!, canEdit: canEdit)
                : _ClinicalNoteReadOnly(note: visit.documentation),
          ),
        ),
        const SizedBox(height: VisitPageTokens.sectionGap),
        VisitSectionGrid(
          children: [
            if (canEdit && docState != null)
              VitalSignList(
                visitId: visitId,
                vitalSigns: visit.vitalSigns,
                predefinedVitalSigns: docState!.predefinedVitalSigns,
                canEdit: canEdit,
                onChanged: onRefresh,
                sectionKind: VisitPanelKind.vitalSigns,
                sectionTitle: 'Vital signs',
              )
            else
              VisitSectionCard(
                kind: VisitPanelKind.vitalSigns,
                title: 'Vital signs',
                child: _VitalSignsReadOnly(vitalSigns: visit.vitalSigns),
              ),
            if (canEdit)
              TreatmentPlanList(
                visitId: visitId,
                treatmentPlans: visit.treatmentPlans,
                canEdit: canEdit,
                onChanged: onRefresh,
                sectionKind: VisitPanelKind.treatment,
                sectionTitle: 'Treatment plans',
              )
            else
              VisitSectionCard(
                kind: VisitPanelKind.treatment,
                title: 'Treatment plans',
                child: _TreatmentPlansReadOnly(treatmentPlans: visit.treatmentPlans),
              ),
            if (canEdit)
              InvestigationList(
                visitId: visitId,
                investigations: visit.investigations,
                canEdit: canEdit,
                onChanged: onRefresh,
                sectionKind: VisitPanelKind.investigation,
                sectionTitle: 'Investigations',
              )
            else
              VisitSectionCard(
                kind: VisitPanelKind.investigation,
                title: 'Investigations',
                child: _InvestigationsReadOnly(investigations: visit.investigations),
              ),
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
        ),
      ],
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
        for (final section in VisitPageTokens.clinicalSections)
          _ClinicalNoteSection(
            key: Key('visit_detail_${section.label.toLowerCase()}'),
            abbr: section.abbr,
            label: section.label,
            value: _valueForSection(note, section.label),
          ),
      ],
    );
  }

  String? _valueForSection(VisitClinicalNote? note, String label) => switch (label) {
    'Complaint' => note?.complaint,
    'History' => note?.history,
    'Examination' => note?.examination,
    'Diagnosis' => note?.diagnosis,
    'Plan' => note?.plan,
    _ => null,
  };
}

class _ClinicalNoteSection extends StatelessWidget {
  const _ClinicalNoteSection({required this.abbr, required this.label, required this.value, super.key});

  final String abbr;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return VisitDetailField(label: label, value: value ?? '', abbr: abbr);
  }
}

class _VitalSignsReadOnly extends StatelessWidget {
  const _VitalSignsReadOnly({required this.vitalSigns});

  final List<VisitVitalSign> vitalSigns;

  @override
  Widget build(BuildContext context) {
    if (vitalSigns.isEmpty) {
      return const VisitEmptyHint(
        key: Key('visit_detail_vital_signs_empty'),
        message: 'No vital signs recorded.',
        icon: Icons.monitor_heart_outlined,
      );
    }

    return Wrap(
      spacing: SpacingTokens.sm,
      runSpacing: SpacingTokens.sm,
      children: [for (final sign in vitalSigns) VitalSignCardView(sign: sign)],
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
