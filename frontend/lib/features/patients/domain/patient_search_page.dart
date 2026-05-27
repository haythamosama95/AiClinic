import 'package:ai_clinic/features/patients/domain/patient_list_item.dart';

/// Paginated patient list/search result from `search_patients`.
class PatientSearchPage {
  const PatientSearchPage({required this.items, required this.totalCount, required this.limit, required this.offset});

  final List<PatientListItem> items;
  final int totalCount;
  final int limit;
  final int offset;

  factory PatientSearchPage.fromRpcData(Map<String, dynamic>? data) {
    if (data == null) {
      return const PatientSearchPage(items: [], totalCount: 0, limit: 25, offset: 0);
    }

    final rawItems = data['items'];
    final items = <PatientListItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          final item = PatientListItem.fromRow(Map<String, dynamic>.from(entry));
          if (item != null) {
            items.add(item);
          }
        }
      }
    }

    return PatientSearchPage(
      items: items,
      totalCount: _readInt(data['total_count'], fallback: items.length),
      limit: _readInt(data['limit'], fallback: 25),
      offset: _readInt(data['offset'], fallback: 0),
    );
  }

  static int _readInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
