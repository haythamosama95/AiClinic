import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_detail.dart';

/// Read-only visit detail for history drill-down (V1-5 US6).
final visitDetailProvider = FutureProvider.autoDispose.family<VisitDetail, String>((ref, visitId) async {
  final id = visitId.trim();
  if (id.isEmpty) {
    throw StateError('Visit id is required.');
  }
  return ref.read(visitRepositoryProvider).getVisit(visitId: id);
});
