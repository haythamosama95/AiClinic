import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/visits/domain/soap_note.dart';
import 'package:ai_clinic/features/visits/domain/treatment_plan_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_attachment_item.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_detail_provider.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Visit detail')),
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
        data: (visit) => _VisitDetailBody(visit: visit),
      ),
    );
  }
}

class _VisitDetailBody extends StatelessWidget {
  const _VisitDetailBody({required this.visit});

  final VisitDetail visit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel = DateFormat.yMMMd().format(visit.visitDate.toLocal());

    return ListView(
      key: const Key('visit_detail_body'),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Visit on $dateLabel', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        _DetailRow(label: 'Doctor', value: visit.doctorName),
        _DetailRow(label: 'Status', value: visit.status.label),
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
          ...visit.treatmentPlans.map((plan) => _TreatmentPlanCard(plan: plan)),
        ],
        if (visit.attachments.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Attachments', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ...visit.attachments.map((attachment) => _AttachmentRow(attachment: attachment)),
        ],
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

class _TreatmentPlanCard extends StatelessWidget {
  const _TreatmentPlanCard({required this.plan});

  final TreatmentPlanItem plan;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(plan.medicationName),
        subtitle: Text(
          [
            if (plan.dosage != null && plan.dosage!.isNotEmpty) plan.dosage,
            if (plan.frequency != null && plan.frequency!.isNotEmpty) plan.frequency,
            if (plan.notes != null && plan.notes!.isNotEmpty) plan.notes,
          ].whereType<String>().join(' · '),
        ),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachment});

  final VisitAttachmentItem attachment;

  @override
  Widget build(BuildContext context) {
    final label = attachment.label?.trim().isNotEmpty == true ? attachment.label! : attachment.fileType.label;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.attach_file),
      title: Text(label),
      subtitle: Text('${attachment.fileType.label} · ${attachment.sizeBytes} bytes'),
    );
  }
}
