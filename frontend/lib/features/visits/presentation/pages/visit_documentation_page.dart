import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/soap_editor.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/specialty_form_fields.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_submit_dialog.dart';

/// Visit documentation — SOAP and related sections (V1-5).
class VisitDocumentationPage extends ConsumerWidget {
  const VisitDocumentationPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = visitId?.trim();
    if (id == null || id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visit documentation')),
        body: const Center(child: Text('Visit not found.')),
      );
    }

    final docAsync = ref.watch(visitDocumentationProvider(id));
    final canEditSoap = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit documentation'),
        actions: [
          docAsync.maybeWhen(
            data: (state) {
              if (!canEditSoap) {
                return null;
              }
              if (state.visit.status == VisitStatus.inProgress) {
                return TextButton.icon(
                  key: const Key('visit_submit_button'),
                  onPressed: () => _submitVisit(context, ref, id, state),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Submit visit'),
                );
              }
              if (state.visit.status == VisitStatus.completed) {
                final isSaving = state.saveStatus == SoapSaveStatus.saving;
                return TextButton.icon(
                  key: const Key('visit_save_close_button'),
                  onPressed: isSaving ? null : () => _saveAndClose(context, ref, id),
                  icon: isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(isSaving ? 'Saving…' : 'Save & close'),
                );
              }
              return null;
            },
            orElse: () => null,
          ),
        ].whereType<Widget>().toList(),
      ),
      body: docAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(visitDocumentationProvider(id)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (state) => _VisitHeaderAndSoap(visitId: id, state: state),
      ),
    );
  }

  Future<void> _submitVisit(BuildContext context, WidgetRef ref, String visitId, VisitDocumentationState state) async {
    final result = await VisitSubmitDialog.show(context, visitId: visitId, expectedUpdatedAt: state.expectedUpdatedAt);

    if (result == null || !context.mounted) {
      return;
    }

    ref.invalidate(visitDocumentationProvider(visitId));

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Visit submitted. The linked appointment is now completed.')));
  }

  Future<void> _saveAndClose(BuildContext context, WidgetRef ref, String visitId) async {
    final current = ref.read(visitDocumentationProvider(visitId)).value;
    if (current == null) {
      return;
    }

    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final messenger = ScaffoldMessenger.of(context);
    var savedChanges = false;

    if (current.needsSaveBeforeLeaving) {
      await notifier.save();
      if (!context.mounted) {
        return;
      }
      final updated = ref.read(visitDocumentationProvider(visitId)).value;
      if (updated == null || updated.saveStatus == SoapSaveStatus.error || updated.saveStatus == SoapSaveStatus.stale) {
        return;
      }
      savedChanges = true;
    }

    if (!context.mounted) {
      return;
    }
    _leaveDocumentation(context, visitId);
    if (savedChanges) {
      messenger.showSnackBar(const SnackBar(content: Text('Changes saved.')));
    }
  }

  void _leaveDocumentation(BuildContext context, String visitId) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.visitDetail(visitId));
  }
}

class _VisitHeaderAndSoap extends ConsumerWidget {
  const _VisitHeaderAndSoap({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;
    final dateLabel = DateFormat.yMMMd().format(visit.visitDate.toLocal());
    final canUploadAttachments = ref.watch(permissionServiceProvider).canUploadVisitAttachments();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Visit on $dateLabel', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Doctor: ${visit.doctorName}'),
        const SizedBox(height: 4),
        Text('Status: ${visit.status.label}'),
        if (!state.specialtySchema.hasFields && state.canEdit) ...[
          const SizedBox(height: 16),
          MaterialBanner(
            key: const Key('specialty_schema_empty_banner'),
            content: const Text('No specialty form configured. Configure in Organization settings.'),
            actions: [
              TextButton(
                key: const Key('specialty_schema_settings_link'),
                onPressed: () => context.go(AppRoutes.settingsOrganization),
                child: const Text('Organization settings'),
              ),
            ],
          ),
        ],
        if (state.specialtySchema.hasFields) ...[
          const SizedBox(height: 24),
          Text('Specialty fields', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SpecialtyFormFields(visitId: visitId, state: state),
        ],
        const SizedBox(height: 24),
        Text('SOAP note', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SoapEditor(visitId: visitId, state: state),
        const SizedBox(height: 24),
        TreatmentPlanList(
          visitId: visitId,
          treatmentPlans: state.visit.treatmentPlans,
          canEdit: state.canEdit,
          onChanged: () =>
              ref.read(visitDocumentationProvider(visitId).notifier).refreshTreatmentPlansPreservingDraft(),
        ),
        const SizedBox(height: 24),
        VisitAttachmentList(
          visitId: visitId,
          branchId: visit.branchId,
          attachments: state.visit.attachments,
          canUpload: canUploadAttachments,
          onChanged: () =>
              ref.read(visitDocumentationProvider(visitId).notifier).refreshTreatmentPlansPreservingDraft(),
        ),
      ],
    );
  }
}
