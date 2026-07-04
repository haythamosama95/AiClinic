import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/widgets.dart';

import 'pattern_scaffold.dart';

/// List / index page scaffold — toolbar, table, pagination, and bulk actions.
///
/// Composes [AppPageHeader] → [AppToolbar] → optional filter chips →
/// [AppBulkActionBar] → [AppTable] → [AppPagination]. Table loading, empty,
/// error, and filtered-empty states are passed through via [table].
class ListIndexPattern extends StatelessWidget {
  const ListIndexPattern({
    required this.title,
    required this.table,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.description,
    this.breadcrumb,
    this.headerActions,
    this.toolbarStart,
    this.toolbarCenter,
    this.toolbarEnd,
    this.toolbarCompactEnd,
    this.filterChips,
    this.selectedCount = 0,
    this.bulkItemLabel = 'selected',
    this.bulkActions,
    this.onClearSelection,
    this.pageSizeSelect,
    this.paginationLabel = 'Pagination',
    super.key,
  });

  final String title;
  final String? description;
  final Widget? breadcrumb;
  final Widget? headerActions;
  final Widget? toolbarStart;
  final Widget? toolbarCenter;
  final Widget? toolbarEnd;
  final Widget? toolbarCompactEnd;
  final Widget? filterChips;
  final Widget table;
  final int selectedCount;
  final String bulkItemLabel;
  final Widget? bulkActions;
  final VoidCallback? onClearSelection;
  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final Widget? pageSizeSelect;
  final String paginationLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = PatternScaffold.pagePadding(constraints.maxWidth);
        final showBulk = selectedCount > 0 && onClearSelection != null;

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPageHeader(
                title: title,
                description: description,
                breadcrumb: breadcrumb,
                actions: headerActions,
              ),
              const SizedBox(height: PatternScaffold.headerToolbarGap),
              AppToolbar(
                start: toolbarStart,
                center: toolbarCenter,
                end: toolbarEnd,
                compactEnd: toolbarCompactEnd,
              ),
              if (filterChips != null) ...[
                const SizedBox(height: AppSpacing.s3),
                filterChips!,
              ],
              if (showBulk) ...[
                const SizedBox(height: AppSpacing.s3),
                AppBulkActionBar(
                  visible: true,
                  selectedCount: selectedCount,
                  itemLabel: bulkItemLabel,
                  onClear: onClearSelection!,
                  actions: bulkActions,
                ),
              ],
              const SizedBox(height: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: table),
                    const SizedBox(height: AppSpacing.s4),
                    AppPagination(
                      page: page,
                      pageCount: pageCount,
                      onPageChanged: onPageChanged,
                      pageSizeSelect: pageSizeSelect,
                      semanticLabel: paginationLabel,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
