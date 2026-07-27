import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_clinic/features/visits/data/visit_repository.dart';
import 'package:ai_clinic/features/visits/domain/catalog_item.dart';

const catalogSearchDebounce = Duration(milliseconds: 300);
const catalogSearchMinLength = 2;

int _investigationSearchGeneration = 0;
int _medicationSearchGeneration = 0;

Never? _disableCatalogSearchRetry(int retryCount, Object error) => null;

Future<List<CatalogItem>> _debouncedCatalogSearch(
  Ref ref,
  String query,
  int Function() nextGeneration,
  int Function() readGeneration,
  Future<List<CatalogItem>> Function(VisitRepository repo, String trimmedQuery) search,
) async {
  final trimmed = query.trim();
  if (trimmed.length < catalogSearchMinLength) {
    return const [];
  }

  final keepAliveLink = ref.keepAlive();
  final generation = nextGeneration();

  await Future<void>.delayed(catalogSearchDebounce);
  if (!ref.mounted || generation != readGeneration()) {
    keepAliveLink.close();
    return const [];
  }

  try {
    final items = await search(ref.read(visitRepositoryProvider), trimmed);
    keepAliveLink.close();
    ref.keepAlive();
    return items;
  } on Object {
    rethrow;
  }
}

/// Debounced investigation catalog search for visit documentation dialogs.
final investigationSearchProvider = FutureProvider.autoDispose.family<List<CatalogItem>, String>(
  (ref, query) => _debouncedCatalogSearch(
    ref,
    query,
    () => ++_investigationSearchGeneration,
    () => _investigationSearchGeneration,
    (repo, trimmed) => repo.searchInvestigations(query: trimmed),
  ),
  retry: _disableCatalogSearchRetry,
);

/// Debounced medication catalog search for visit documentation dialogs.
final medicationSearchProvider = FutureProvider.autoDispose.family<List<CatalogItem>, String>(
  (ref, query) => _debouncedCatalogSearch(
    ref,
    query,
    () => ++_medicationSearchGeneration,
    () => _medicationSearchGeneration,
    (repo, trimmed) => repo.searchMedications(query: trimmed),
  ),
  retry: _disableCatalogSearchRetry,
);

/// @visibleForTesting
void resetCatalogSearchGenerationsForTest() {
  _investigationSearchGeneration = 0;
  _medicationSearchGeneration = 0;
}
