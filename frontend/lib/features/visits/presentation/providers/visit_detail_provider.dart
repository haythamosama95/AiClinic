import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/app/providers/auth_session_provider.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';

/// Visit detail screen state including permission-derived edit flags (013 US6).
@immutable
class VisitDetailViewState {
  const VisitDetailViewState({
    required this.visit,
    required this.canEditDocumentation,
    required this.hasBranchAccess,
    required this.canUploadAttachments,
  });

  final VisitDetail visit;
  final bool canEditDocumentation;
  final bool hasBranchAccess;
  final bool canUploadAttachments;
}

/// Read-only visit detail for history drill-down with permission gating (013 US6).
final visitDetailViewProvider = FutureProvider.autoDispose.family<VisitDetailViewState, String>((ref, visitId) async {
  final id = visitId.trim();
  if (id.isEmpty) {
    throw StateError('Visit id is required.');
  }

  final visit = await ref.read(visitRepositoryProvider).getVisit(visitId: id);
  final auth = ref.watch(authSessionProvider);
  final permissions = ref.watch(permissionServiceProvider);
  final branchIds = auth.context?.branchIds ?? const <String>[];
  final hasBranchAccess = branchIds.contains(visit.branchId);
  final canEditSoap = permissions.canEditVisitSoap();

  return VisitDetailViewState(
    visit: visit,
    canEditDocumentation: canEditSoap && hasBranchAccess,
    hasBranchAccess: hasBranchAccess,
    canUploadAttachments: permissions.canUploadVisitAttachments(),
  );
});

/// @deprecated Use [visitDetailViewProvider] for permission-aware detail screens.
final visitDetailProvider = FutureProvider.autoDispose.family<VisitDetail, String>((ref, visitId) async {
  return ref.watch(visitDetailViewProvider(visitId).future).then((view) => view.visit);
});
