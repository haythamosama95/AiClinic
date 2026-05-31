import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/core/data/paginated_list_notifier.dart';
import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/visit_list_item.dart';

/// Paginated visit history for a patient profile (V1-5 US6).
class PatientVisitHistoryNotifier extends PaginatedListNotifier<VisitListItem> {
  PatientVisitHistoryNotifier(this._patientId);

  final String _patientId;

  @override
  int get pageSize => 20;

  @override
  Future<PaginatedPage<VisitListItem>> fetchPage(int offset, int limit) async {
    final page = await ref
        .read(visitRepositoryProvider)
        .listPatientVisits(patientId: _patientId, limit: limit, offset: offset);

    return PaginatedPage(items: page.items, totalCount: page.totalCount, offset: page.offset, limit: page.limit);
  }
}

final patientVisitHistoryProvider = AsyncNotifierProvider.autoDispose
    .family<PatientVisitHistoryNotifier, PaginatedList<VisitListItem>, String>(PatientVisitHistoryNotifier.new);
