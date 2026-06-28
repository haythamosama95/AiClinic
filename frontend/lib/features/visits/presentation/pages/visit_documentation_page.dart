import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/soap_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/specialty_form_fields.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';

/// Visit documentation — SOAP and related sections (V1-5).
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
    final canEditSoap = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return docAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit documentation…'),
      error: (error, _) => _VisitDocumentationError(
        message: error.toString(),
        onRetry: () => ref.invalidate(visitDocumentationProvider(id)),
        onBack: () => _goBack(context, id),
      ),
      data: (state) => _VisitDocumentationScaffold(
        headerActions: [
          VisitDetailActions(visitId: id, status: state.visit.status),
          if (canEditSoap && state.visit.status == VisitStatus.inProgress)
            AppButton(
              key: const Key('visit_submit_button'),
              label: 'Submit visit',
              icon: const Icon(Icons.check_circle_outline, size: 18),
              onPressed: () => _submitVisit(context, ref, id, state),
            )
          else if (canEditSoap && state.visit.status == VisitStatus.completed)
            AppButton(
              key: const Key('visit_save_close_button'),
              label: state.saveStatus == SoapSaveStatus.saving ? 'Saving…' : 'Save & close',
              variant: AppButtonVariant.outline,
              isLoading: state.saveStatus == SoapSaveStatus.saving,
              onPressed: state.saveStatus == SoapSaveStatus.saving ? null : () => _saveAndClose(context, ref, id),
            ),
        ],
        onBack: () => _goBack(context, id),
        body: _VisitDocumentationBody(visitId: id, state: state),
      ),
    );
  }

  static void _goBack(BuildContext context, String visitId) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.visitDetail(visitId));
  }

  Future<void> _submitVisit(BuildContext context, WidgetRef ref, String visitId, VisitDocumentationState state) async {
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);

    if (state.needsSaveBeforeLeaving) {
      await notifier.save();
      if (!context.mounted) return;
      final updated = ref.read(visitDocumentationProvider(visitId)).value;
      if (updated == null || updated.saveStatus == SoapSaveStatus.error || updated.saveStatus == SoapSaveStatus.stale) {
        return;
      }
    }

    final latest = ref.read(visitDocumentationProvider(visitId)).value ?? state;
    final result = await VisitSubmitDialog.show(context, visitId: visitId, expectedUpdatedAt: latest.expectedUpdatedAt);

    if (result == null || !context.mounted) return;

    ref.invalidate(visitDocumentationProvider(visitId));
    AppToast.success(context, message: 'Visit submitted. The linked appointment is now completed.');
  }

  Future<void> _saveAndClose(BuildContext context, WidgetRef ref, String visitId) async {
    final current = ref.read(visitDocumentationProvider(visitId)).value;
    if (current == null) return;

    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    var savedChanges = false;

    if (current.needsSaveBeforeLeaving) {
      await notifier.save();
      if (!context.mounted) return;
      final updated = ref.read(visitDocumentationProvider(visitId)).value;
      if (updated == null || updated.saveStatus == SoapSaveStatus.error || updated.saveStatus == SoapSaveStatus.stale) {
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
  const _VisitDocumentationBody({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;
    final dateLabel = DateFormat('EEEE, MMM d, yyyy').format(visit.visitDate.toLocal());
    final canUploadAttachments = ref.watch(permissionServiceProvider).canUploadVisitAttachments();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.clamp(0, 920).toDouble();

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                VisitHeroCard(dateLabel: dateLabel, doctorName: visit.doctorName, status: visit.status),
                if (!state.specialtySchema.hasFields && state.canEdit) ...[
                  const SizedBox(height: SpacingTokens.lg),
                  AppAlert(
                    key: const Key('specialty_schema_empty_banner'),
                    title: 'No specialty form configured.',
                    subtitle: 'Configure custom fields in Organization settings.',
                    icon: const Icon(Icons.tune_outlined),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      key: const Key('specialty_schema_settings_link'),
                      label: 'Organization settings',
                      variant: AppButtonVariant.outline,
                      onPressed: () => context.go(AppRoutes.settingsOrganization),
                    ),
                  ),
                ],
                if (state.specialtySchema.hasFields) ...[
                  const SizedBox(height: SpacingTokens.lg),
                  VisitSectionCard(
                    title: 'Specialty fields',
                    description: 'Clinic-specific clinical fields',
                    child: SpecialtyFormFields(visitId: visitId, state: state),
                  ),
                ],
                const SizedBox(height: SpacingTokens.lg),
                VisitSectionCard(
                  title: 'SOAP note',
                  description: 'Document subjective, objective, assessment, and plan',
                  child: SoapEditor(visitId: visitId, state: state),
                ),
                const SizedBox(height: SpacingTokens.lg),
                VisitSectionCard(
                  title: 'Treatment plans',
                  description: 'Prescriptions and medication instructions',
                  child: TreatmentPlanList(
                    visitId: visitId,
                    treatmentPlans: state.visit.treatmentPlans,
                    canEdit: state.canEdit,
                    onChanged: () => ref.read(visitDocumentationProvider(visitId).notifier).refreshVisitPreservingDraft(),
                  ),
                ),
                const SizedBox(height: SpacingTokens.lg),
                VisitSectionCard(
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
          ),
        );
      },
    );
  }
}

class _VisitDocumentationScaffold extends StatelessWidget {
  const _VisitDocumentationScaffold({
    required this.headerActions,
    required this.onBack,
    required this.body,
  });

  final List<Widget> headerActions;
  final VoidCallback onBack;
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
              AppIconButton(
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: 'Back',
                onPressed: onBack,
              ),
              const Spacer(),
              ...headerActions.map(
                (action) => Padding(padding: const EdgeInsets.only(left: SpacingTokens.sm), child: action),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Expanded(
            child: SingleChildScrollView(
              child: body,
            ),
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
    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppIconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Back', onPressed: onBack),
          ),
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
