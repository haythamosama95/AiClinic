import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/app/app_routes.dart';
import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/domain/specialty_form_schema.dart';
import 'package:ai_clinic/features/visits/domain/soap_note.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/treatment_plan_display.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/specialty_form_schema_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/specialty_form_read_only_section.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_attachment_list.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_detail_actions.dart';

/// Read-only clinical visit detail from patient history (V1-5 US6).
class VisitDetailPage extends ConsumerWidget {
  const VisitDetailPage({required this.visitId, super.key});

  final String? visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = visitId?.trim();
    if (id == null || id.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visit detail')),
        body: const Center(child: Text('Visit not found.')),
      );
    }

    final detailAsync = ref.watch(visitDetailProvider(id));
    final schemaAsync = ref.watch(specialtyFormSchemaProvider);
    final canEdit = ref.watch(permissionServiceProvider).canEditVisitSoap();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit detail'),
        actions: [
          detailAsync.maybeWhen(
            data: (visit) => VisitDetailActions(visitId: id, status: visit.status),
            orElse: () => null,
          ),
          detailAsync.maybeWhen(
            data: (visit) {
              if (!canEdit) return null;
              return TextButton(
                key: const Key('visit_detail_edit_documentation'),
                onPressed: () => context.push(AppRoutes.visitDocument(id)),
                child: Text(visit.status == VisitStatus.inProgress ? 'Edit documentation' : 'Edit visit'),
              );
            },
            orElse: () => null,
          ),
        ].whereType<Widget>().toList(),
      ),
      body: detailAsync.when(
        loading: () => const Center(key: Key('visit_detail_loading'), child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => ref.invalidate(visitDetailProvider(id)), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (visit) => schemaAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _VisitDetailBody(visit: visit, schema: const SpecialtyFormSchema()),
          data: (schema) => _VisitDetailBody(visit: visit, schema: schema),
        ),
      ),
    );
  }
}

class _VisitDetailBody extends StatelessWidget {
  const _VisitDetailBody({required this.visit, required this.schema});

  final VisitDetail visit;
  final SpecialtyFormSchema schema;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMd().format(visit.visitDate.toLocal());
    final specialtyValues = visit.soap?.specialtyFormJson ?? const {};

    return ListView(
      key: const Key('visit_detail_body'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Visit on $dateLabel', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        _DetailRow(label: 'Doctor', value: visit.doctorName),
        _DetailRow(label: 'Status', value: visit.status.label),
        if (specialtyValues.isNotEmpty) ...[
          const SizedBox(height: 24),
          SpecialtyFormReadOnlySection(values: specialtyValues, schema: schema),
        ],
        if (visit.soap != null) ...[
          const SizedBox(height: 24),
          Text('SOAP note', key: const Key('visit_detail_soap_section'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          _SoapSections(soap: visit.soap!),
        ],
        if (visit.treatmentPlans.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Treatment plans', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...visit.treatmentPlans.map((plan) => TreatmentPlanCardView(plan: plan)),
        ],
        const SizedBox(height: 24),
        VisitAttachmentList(
          visitId: visit.id,
          branchId: visit.branchId,
          attachments: visit.attachments,
          canUpload: false,
          onChanged: () {},
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('$label: $value'));
  }
}

class _SoapSections extends StatelessWidget {
  const _SoapSections({required this.soap});

  final SoapNote soap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SoapSection(key: const Key('visit_detail_subjective'), label: 'Subjective', value: soap.subjective),
        _SoapSection(key: const Key('visit_detail_objective'), label: 'Objective', value: soap.objective),
        _SoapSection(key: const Key('visit_detail_assessment'), label: 'Assessment', value: soap.assessment),
        _SoapSection(key: const Key('visit_detail_plan'), label: 'Plan', value: soap.plan),
      ],
    );
  }
}

class _SoapSection extends StatelessWidget {
  const _SoapSection({required this.label, required this.value, super.key});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final display = value?.trim().isNotEmpty == true ? value!.trim() : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(display),
        ],
      ),
    );
  }
}
