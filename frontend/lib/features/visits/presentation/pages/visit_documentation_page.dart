import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/soap_editor.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('Visit documentation')),
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
}

class _VisitHeaderAndSoap extends StatelessWidget {
  const _VisitHeaderAndSoap({required this.visitId, required this.state});

  final String visitId;
  final VisitDocumentationState state;

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 24),
        Text('SOAP note', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        SoapEditor(visitId: visitId, state: state),
      ],
    );
  }
}
