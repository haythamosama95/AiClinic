import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_investigations_editor.dart';

/// Investigations editor block (web `InvestigationsEditor`).
class InvestigationsEditor extends ConsumerWidget {
  const InvestigationsEditor({required this.visitId, super.key});

  final String visitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = ref.watch(visitDocumentationProvider(visitId));
    final state = doc.value;
    if (state == null) {
      return const SizedBox.shrink();
    }

    final canEdit = state.canEditWorkspace(ref.read(permissionServiceProvider).canEditVisitSoap());
    final notifier = ref.read(visitDocumentationProvider(visitId).notifier);
    final investigations = state.effectiveVisit.investigations;

    return VisitInvestigationsEditor(
      entries: investigations,
      canEdit: canEdit,
      onCreate: ({required name, note, investigationId}) =>
          notifier.stageCreateInvestigation(name: name, note: note, investigationId: investigationId),
      onUpdate: (id, {required name, note, investigationId}) => notifier.stageUpdateInvestigation(
        investigationLineId: id,
        name: name,
        note: note,
        investigationId: investigationId,
        updateInvestigationId: true,
      ),
      onArchive: notifier.stageArchiveInvestigation,
    );
  }
}
