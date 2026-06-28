import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/core/ui/theme/spacing_tokens.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_full_page_loading.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';
import 'package:ai_clinic/features/visits/domain/visit_clinical_note.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_shared_widgets.dart';

/// Read-only clinical visit detail from patient history (V1-5 US6).
class VisitDetailPage extends ConsumerWidget {
  const VisitDetailPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = visitId?.trim();
    if (id == null || id.isEmpty) {
      return const _VisitNotFound(message: 'Visit not found.');
    }

    final detailAsync = ref.watch(visitDetailProvider(id));
    final canEdit = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return detailAsync.when(
      loading: () => const AppFullPageLoading(message: 'Loading visit…'),
      error: (error, _) => _VisitDetailError(
        message: error.toString(),
        onRetry: () => ref.invalidate(visitDetailProvider(id)),
        onBack: () => _goBack(context),
      ),
      data: (visit) => _VisitDetailContentView(visit: visit, canEdit: canEdit, onBack: () => _goBack(context)),
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

class _VisitDetailContentView extends StatelessWidget {
  const _VisitDetailContentView({required this.visit, required this.canEdit, required this.onBack});

  final VisitDetail visit;
  final bool canEdit;
  final VoidCallback onBack;

  static final _dateFormat = DateFormat('EEEE, MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    final note = visit.documentation;

    return Padding(
      padding: const EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIconButton(icon: const Icon(Icons.arrow_back, size: 18), tooltip: 'Back', onPressed: onBack),
              const Spacer(),
              VisitDetailActions(visitId: visit.id, status: visit.status),
              if (canEdit) ...[
                const SizedBox(width: SpacingTokens.sm),
                AppButton(
                  key: const Key('visit_detail_edit_documentation'),
                  label: visit.status == VisitStatus.inProgress ? 'Edit documentation' : 'Edit visit',
                  variant: AppButtonVariant.outline,
                  onPressed: () => context.push(AppRoutes.visitDocument(visit.id)),
                ),
              ],
            ],
          ),
          const SizedBox(height: SpacingTokens.md),
          Expanded(
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Column(
                    key: const Key('visit_detail_body'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      VisitHeroCard(
                        dateLabel: _dateFormat.format(visit.visitDate.toLocal()),
                        doctorName: visit.doctorName,
                        status: visit.status,
                      ),
                      if (note != null && note.hasContent) ...[
                        const SizedBox(height: SpacingTokens.lg),
                        VisitSectionCard(
                          title: 'Clinical note',
                          child: KeyedSubtree(
                            key: const Key('visit_detail_clinical_note_section'),
                            child: _ClinicalNoteSections(note: note),
                          ),
                        ),
                      ],
                      if (visit.treatmentPlans.isNotEmpty) ...[
                        const SizedBox(height: SpacingTokens.lg),
                        VisitSectionCard(
                          title: 'Treatment plans',
                          child: Column(
                            children: [
                              for (final plan in visit.treatmentPlans)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
                                  child: TreatmentPlanCardView(plan: plan),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: SpacingTokens.lg),
                      VisitSectionCard(
                        title: 'Attachments',
                        child: VisitAttachmentList(
                          visitId: visit.id,
                          branchId: visit.branchId,
                          attachments: visit.attachments,
                          canUpload: false,
                          onChanged: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalNoteSections extends StatelessWidget {
  const _ClinicalNoteSections({required this.note});

  final VisitClinicalNote note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ClinicalNoteSection(key: const Key('visit_detail_complaint'), label: 'Complaint', value: note.complaint),
        _ClinicalNoteSection(key: const Key('visit_detail_history'), label: 'History', value: note.history),
        _ClinicalNoteSection(key: const Key('visit_detail_examination'), label: 'Examination', value: note.examination),
        _ClinicalNoteSection(key: const Key('visit_detail_diagnosis'), label: 'Diagnosis', value: note.diagnosis),
        _ClinicalNoteSection(key: const Key('visit_detail_plan'), label: 'Plan', value: note.plan),
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
