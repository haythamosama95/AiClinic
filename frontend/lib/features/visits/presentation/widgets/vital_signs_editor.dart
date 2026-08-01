import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_notifier.dart';
import 'package:ai_clinic/features/visits/presentation/widgets/visit_vital_signs_editor.dart';

/// Vital signs editor block (web `VitalSignsEditor`).
class VitalSignsEditor extends ConsumerWidget {
  const VitalSignsEditor({required this.visitId, super.key});

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
    final signs = state.effectiveVisit.vitalSigns;
    final catalog = state.predefinedVitalSigns;

    return VisitVitalSignsEditor(
      entries: signs,
      catalog: catalog,
      canEdit: canEdit,
      onCreate: ({required name, required value, unit, predefinedVitalSignId}) => notifier.stageCreateVitalSign(
        name: name,
        value: value,
        unit: unit,
        predefinedVitalSignId: predefinedVitalSignId,
      ),
      onUpdate: (id, {required name, required value, unit, predefinedVitalSignId}) => notifier.stageUpdateVitalSign(
        vitalSignId: id,
        name: name,
        value: value,
        unit: unit,
        predefinedVitalSignId: predefinedVitalSignId,
      ),
      onArchive: notifier.stageArchiveVitalSign,
    );
  }
}
