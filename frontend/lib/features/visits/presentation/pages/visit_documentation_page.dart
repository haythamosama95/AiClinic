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
    final canSubmit = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit documentation'),
        actions: [
          docAsync.maybeWhen(
            data: (state) {
              if (!canSubmit || state.visit.status != VisitStatus.inProgress) {
                return null;
              }
              return TextButton.icon(
                key: const Key('visit_submit_button'),
                onPressed: () => _submitVisit(context, ref, id, state),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Submit visit'),
              );
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
}

class _VisitHeaderAndSoap extends ConsumerWidget {
  const _VisitHeaderAndSoap({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visit = state.visit;
    final dateLabel = DateFormat.yMMMd().format(visit.visitDate.toLocal());

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
      ],
    );
  }
}
