import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_badge.dart';
import 'package:ai_clinic/core/ui/components/app_bulk_action_bar.dart';
import 'package:ai_clinic/core/ui/components/app_button.dart';
import 'package:ai_clinic/core/ui/components/app_chip.dart';
import 'package:ai_clinic/core/ui/components/app_data_table.dart';
import 'package:ai_clinic/core/ui/components/app_money_display.dart';
import 'package:ai_clinic/core/ui/components/app_page_header.dart';
import 'package:ai_clinic/core/ui/components/app_pagination.dart';
import 'package:ai_clinic/core/ui/components/app_search_input.dart';
import 'package:ai_clinic/core/ui/components/app_select.dart';
import 'package:ai_clinic/core/ui/components/app_toolbar.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/pattern_frame.dart';
import 'package:ai_clinic/features/design_system/presentation/patterns/pattern_mock_data.dart';
import 'package:ai_clinic/features/design_system/presentation/widgets/showcase_primitives.dart';

/// List / index pattern (web `ListIndexPattern`).
class ListIndexPattern extends StatefulWidget {
  const ListIndexPattern({super.key});

  @override
  State<ListIndexPattern> createState() => _ListIndexPatternState();
}

class _ListIndexPatternState extends State<ListIndexPattern> {
  late final TextEditingController _searchController = TextEditingController();
  var _category = 'all';
  var _page = 1;
  var _pageSize = 5;
  final _selected = <String>{};
  String? _sortCol = 'price';
  SortDirection? _sortDir = SortDirection.asc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PatternServiceRow> get _filtered {
    var rows = kPatternMockServices;
    final search = _searchController.text;
    if (search.isNotEmpty) {
      final query = search.toLowerCase();
      rows = rows
          .where((row) => row.name.toLowerCase().contains(query) || row.category.toLowerCase().contains(query))
          .toList();
    }
    if (_category != 'all') {
      rows = rows.where((row) => row.category.toLowerCase() == _category).toList();
    }
    if (_sortCol == 'price' && _sortDir != null) {
      rows = [...rows]
        ..sort(
          (a, b) => _sortDir == SortDirection.asc
              ? a.defaultPrice.compareTo(b.defaultPrice)
              : b.defaultPrice.compareTo(a.defaultPrice),
        );
    }
    return rows;
  }

  void _handleSort(String column) {
    setState(() {
      if (_sortCol == column) {
        _sortDir = _sortDir == SortDirection.asc
            ? SortDirection.desc
            : _sortDir == SortDirection.desc
            ? null
            : SortDirection.asc;
      } else {
        _sortCol = column;
        _sortDir = SortDirection.asc;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final paged = filtered.skip((_page - 1) * _pageSize).take(_pageSize).toList();

    final columns = <TableColumn<PatternServiceRow>>[
      TableColumn(
        id: 'name',
        header: 'Service',
        accessor: (row) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.name, style: AppTypography.bodyStrong(context)),
            Text(row.category, style: AppTypography.caption(context)),
          ],
        ),
      ),
      TableColumn(
        id: 'price',
        header: 'Default price',
        align: TableAlign.end,
        sortable: true,
        accessor: (row) => AppMoneyDisplay(amount: row.defaultPrice),
      ),
      TableColumn(
        id: 'branches',
        header: 'Branches',
        align: TableAlign.end,
        accessor: (row) => Text('${row.branches}'),
      ),
      TableColumn(
        id: 'status',
        header: 'Status',
        accessor: (row) => AppBadge(
          label: row.status == 'active' ? 'Active' : 'Inactive',
          color: row.status == 'active' ? BadgeColor.success : BadgeColor.neutral,
          variant: BadgeVariant.soft,
        ),
      ),
    ];

    return ShowcaseSection(
      id: 'pattern-list-index',
      title: 'List / Index',
      componentName: '05 §2 List / Index',
      description: 'Services catalog with toolbar, filters, selectable table, pagination, and bulk actions.',
      child: PatternFrame(
        minHeight: 520,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: 'Services',
                description: 'Organization catalog with per-branch configuration.',
                actions: AppButton(
                  size: AppButtonSize.sm,
                  leadingIcon: const Icon(Icons.add, size: 16),
                  onPressed: () {},
                  child: const Text('Add service'),
                ),
              ),
              const SizedBox(height: AppSpacing.space4),
              AppToolbar(
                start: SizedBox(
                  width: 224,
                  child: AppSearchInput(
                    controller: _searchController,
                    placeholder: 'Search services…',
                    onChanged: (_) => setState(() => _page = 1),
                    resultCount: filtered.length,
                  ),
                ),
                end: AppSelect(
                  value: _category,
                  onChanged: (value) => setState(() {
                    _category = value;
                    _page = 1;
                  }),
                  options: const [
                    AppSelectOption(value: 'all', label: 'All categories'),
                    AppSelectOption(value: 'consultation', label: 'Consultation'),
                    AppSelectOption(value: 'dental', label: 'Dental'),
                    AppSelectOption(value: 'lab', label: 'Lab'),
                    AppSelectOption(value: 'imaging', label: 'Imaging'),
                  ],
                ),
              ),
              if (_category != 'all') ...[
                const SizedBox(height: AppSpacing.space3),
                AppChip(
                  removable: true,
                  selected: true,
                  onRemove: () => setState(() => _category = 'all'),
                  child: Text('Category: $_category'),
                ),
              ],
              if (_selected.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.space3),
                AppBulkActionBar(
                  count: _selected.length,
                  itemLabel: 'services selected',
                  onClear: () => setState(_selected.clear),
                  actions: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        size: AppButtonSize.sm,
                        variant: AppButtonVariant.secondary,
                        onPressed: () {},
                        child: const Text('Set inactive'),
                      ),
                      const SizedBox(width: AppSpacing.space2),
                      AppButton(
                        size: AppButtonSize.sm,
                        variant: AppButtonVariant.ghost,
                        onPressed: () {},
                        child: const Text('Export'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.space4),
              AppDataTable<PatternServiceRow>(
                columns: columns,
                data: paged,
                getRowId: (row) => row.id,
                selectable: true,
                selectedIds: _selected,
                onSelectionChange: (ids) => setState(() {
                  _selected
                    ..clear()
                    ..addAll(ids);
                }),
                sortColumn: _sortCol,
                sortDirection: _sortDir,
                onSort: _handleSort,
                ariaLabel: 'Services catalog',
              ),
              const SizedBox(height: AppSpacing.space4),
              AppPagination(
                page: _page,
                pageSize: _pageSize,
                total: filtered.length,
                onPageChange: (page) => setState(() => _page = page),
                onPageSizeChange: (size) => setState(() {
                  _pageSize = size;
                  _page = 1;
                }),
                pageSizeOptions: const [5, 10, 25],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
