import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A page of results from a paginated data source.
class PaginatedPage<T> {
  const PaginatedPage({
    required this.items,
    required this.totalCount,
    required this.offset,
    required this.limit,
  });

  final List<T> items;
  final int totalCount;
  final int offset;
  final int limit;
}

/// UI-facing state for a paginated list.
class PaginatedList<T> {
  const PaginatedList({
    required this.items,
    required this.totalCount,
    required this.offset,
    required this.limit,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<T> items;
  final int totalCount;
  final int offset;
  final int limit;
  final bool isLoadingMore;
  final String? loadMoreError;

  bool get hasMore => offset + items.length < totalCount;

  PaginatedList<T> copyWith({
    List<T>? items,
    int? totalCount,
    int? offset,
    int? limit,
    bool? isLoadingMore,
    String? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PaginatedList<T>(
      items: items ?? this.items,
      totalCount: totalCount ?? this.totalCount,
      offset: offset ?? this.offset,
      limit: limit ?? this.limit,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

/// Base class for paginated list notifiers.
///
/// Subclasses implement [fetchPage] to load data from their data source.
abstract class PaginatedListNotifier<T> extends AsyncNotifier<PaginatedList<T>> {
  int get pageSize => 20;

  Future<PaginatedPage<T>> fetchPage(int offset, int limit);

  @override
  Future<PaginatedList<T>> build() async {
    final page = await fetchPage(0, pageSize);
    return PaginatedList<T>(
      items: page.items,
      totalCount: page.totalCount,
      offset: page.offset,
      limit: page.limit,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true, clearLoadMoreError: true));

    try {
      final nextOffset = current.offset + current.limit;
      final page = await fetchPage(nextOffset, pageSize);
      state = AsyncData(PaginatedList<T>(
        items: [...current.items, ...page.items],
        totalCount: page.totalCount,
        offset: page.offset,
        limit: page.limit,
      ));
    } catch (error) {
      state = AsyncData(current.copyWith(
        isLoadingMore: false,
        loadMoreError: error.toString(),
      ));
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}
