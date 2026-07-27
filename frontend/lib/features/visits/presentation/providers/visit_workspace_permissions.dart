import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/domain/visit_status.dart';
import 'package:ai_clinic/features/visits/presentation/providers/visit_documentation_state.dart';

/// Whether the encounter workspace allows structured-data mutations.
bool canMutateVisitWorkspace(Ref ref, String visitId, VisitDocumentationState current) {
  final permissions = ref.read(permissionServiceProvider);
  final branchIds = ref.read(authSessionProvider).context?.branchIds ?? const <String>[];
  final canEdit = permissions.canEditVisitSoap() && branchIds.contains(current.persistedVisit.branchId);
  if (!canEdit) {
    return false;
  }
  if (current.persistedVisit.status == VisitStatus.completed && current.workspaceEditMode != WorkspaceEditMode.editing) {
    return false;
  }
  return true;
}
