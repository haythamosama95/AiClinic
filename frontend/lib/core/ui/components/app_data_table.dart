import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'app_data_table_animated_body.dart';

enum TableDensity { compact, standard, comfortable }

enum TableAlign { start, end, center }

enum SortDirection { asc, desc }

class TableColumn<T> {
  const TableColumn({
    required this.id,
    required this.header,
    required this.accessor,
    this.align = TableAlign.start,
    this.sortable = false,
    this.width,
  });

  final String id;
  final String header;
  final Widget Function(T row) accessor;
  final TableAlign align;
  final bool sortable;
  final double? width;
}

const _selectionColumnName = '__selection__';
const _actionsColumnName = '__actions__';

class _GridRowData<T> {
  const _GridRowData({required this.item, required this.index});

  final T? item;
  final int index;
}

/// Data grid built on Syncfusion [SfDataGrid] (web `DataTable`).
class AppDataTable<T> extends StatefulWidget {
  const AppDataTable({
    required this.columns,
    required this.data,
    required this.getRowId,
    this.density = TableDensity.standard,
    this.zebra = false,
    this.stickyFirstColumn = false,
    this.selectable = false,
    this.selectedIds = const {},
    this.onSelectionChange,
    this.sortColumn,
    this.sortDirection,
    this.onSort,
    this.loading = false,
    this.loadingRows = 5,
    this.emptyState,
    this.errorState,
    this.footer,
    this.onRowClick,
    this.rowActions,
    this.animateRows = false,
    this.headerTextStyle,
    this.ariaLabel = 'Data table',
    super.key,
  });

  final List<TableColumn<T>> columns;
  final List<T> data;
  final TableDensity density;
  final bool zebra;
  final bool stickyFirstColumn;
  final bool selectable;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>>? onSelectionChange;
  final String Function(T row) getRowId;
  final String? sortColumn;
  final SortDirection? sortDirection;
  final ValueChanged<String>? onSort;
  final bool loading;
  final int loadingRows;
  final Widget? emptyState;
  final Widget? errorState;
  final Widget? footer;
  final ValueChanged<T>? onRowClick;
  final Widget? Function(T row)? rowActions;
  final bool animateRows;
  final TextStyle? headerTextStyle;
  final String ariaLabel;

  double get rowHeight => switch (density) {
    TableDensity.compact => 36,
    TableDensity.standard => 40,
    TableDensity.comfortable => 48,
  };

  bool get showBodyInTable => loading || (errorState == null && !(data.isEmpty && emptyState != null));

  int get frozenColumnsCount {
    if (!stickyFirstColumn) return 0;
    return selectable ? 2 : 1;
  }

  @override
  State<AppDataTable<T>> createState() => _AppDataTableState<T>();
}

class _AppDataTableState<T> extends State<AppDataTable<T>> {
  late _AppDataGridSource<T> _source;

  @override
  void initState() {
    super.initState();
    _source = _AppDataGridSource<T>(table: widget, context: context);
  }

  @override
  void didUpdateWidget(covariant AppDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source
      ..table = widget
      ..context = context
      ..notifyListeners();
  }

  bool _allSelected() =>
      widget.data.isNotEmpty && widget.data.every((row) => widget.selectedIds.contains(widget.getRowId(row)));

  bool _someSelected() => widget.data.any((row) => widget.selectedIds.contains(widget.getRowId(row)));

  void _toggleAll() {
    final onChange = widget.onSelectionChange;
    if (onChange == null) return;
    if (_allSelected()) {
      onChange({});
    } else {
      onChange(widget.data.map(widget.getRowId).toSet());
    }
  }

  Alignment _cellAlignment(TableAlign align) => switch (align) {
    TableAlign.start => Alignment.centerLeft,
    TableAlign.end => Alignment.centerRight,
    TableAlign.center => Alignment.center,
  };

  TextAlign _textAlign(TableAlign align) => switch (align) {
    TableAlign.start => TextAlign.start,
    TableAlign.end => TextAlign.end,
    TableAlign.center => TextAlign.center,
  };

  Widget _buildSortIcon(String columnId, AppSemanticColors colors) {
    if (widget.sortColumn != columnId) {
      return Icon(Icons.swap_vert, size: 14, color: colors.iconMuted);
    }
    return Icon(
      widget.sortDirection == SortDirection.asc ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: colors.textLink,
    );
  }

  Widget _headerLabel(BuildContext context, TableColumn<T> column, AppSemanticColors colors) {
    final headerStyle = widget.headerTextStyle ?? AppTypography.overline(context).copyWith(color: colors.textTertiary);
    final alignment = _cellAlignment(column.align);

    if (!column.sortable) {
      return Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
        child: Text(column.header, style: headerStyle, textAlign: _textAlign(column.align)),
      );
    }

    final sortState = widget.sortColumn == column.id
        ? (widget.sortDirection == SortDirection.asc ? 'ascending' : 'descending')
        : 'none';

    return Semantics(
      label: '${column.header}, sort $sortState',
      button: true,
      child: TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: colors.textTertiary,
          alignment: alignment,
        ),
        onPressed: widget.onSort == null ? null : () => widget.onSort!(column.id),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(column.header, style: headerStyle),
            const SizedBox(width: AppSpacing.space1),
            _buildSortIcon(column.id, colors),
          ],
        ),
      ),
    );
  }

  List<GridColumn> _buildGridColumns(AppSemanticColors colors) {
    final gridColumns = <GridColumn>[];

    if (widget.selectable) {
      final checkboxState = _someSelected() && !_allSelected()
          ? AppCheckboxState.indeterminate
          : (_allSelected() ? AppCheckboxState.checked : AppCheckboxState.unchecked);
      gridColumns.add(
        GridColumn(
          columnName: _selectionColumnName,
          width: 40,
          allowSorting: false,
          label: Container(
            alignment: Alignment.center,
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
            child: appWrapMaterialInput(
              AppCheckbox(
                value: checkboxState,
                onChanged: widget.onSelectionChange == null ? null : (_) => _toggleAll(),
              ),
            ),
          ),
        ),
      );
    }

    for (final column in widget.columns) {
      gridColumns.add(
        GridColumn(
          columnName: column.id,
          width: column.width ?? double.nan,
          columnWidthMode: column.width != null ? ColumnWidthMode.none : ColumnWidthMode.fill,
          allowSorting: false,
          label: Container(
            color: colors.surfaceMuted,
            alignment: _cellAlignment(column.align),
            child: _headerLabel(context, column, colors),
          ),
        ),
      );
    }

    if (widget.rowActions != null) {
      gridColumns.add(
        GridColumn(
          columnName: _actionsColumnName,
          width: 48,
          allowSorting: false,
          label: Container(
            alignment: Alignment.center,
            color: colors.surfaceMuted,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
            child: Semantics(label: 'Actions', child: const SizedBox.shrink()),
          ),
        ),
      );
    }

    return gridColumns;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          container: true,
          label: widget.ariaLabel,
          child: Container(
            decoration: BoxDecoration(color: colors.surfaceDefault, borderRadius: BorderRadius.circular(AppRadius.lg)),
            // Foreground border stays above row hover layers (background borders are
            // painted under children and get covered by InkWell / hover fills).
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: colors.borderDefault),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.animateRows && widget.showBodyInTable)
                    _buildAnimatedTable(context, colors)
                  else
                    _buildGridTable(context, colors),
                  if (!widget.loading && widget.errorState != null)
                    widget.errorState!
                  else if (!widget.loading && widget.data.isEmpty && widget.emptyState != null)
                    widget.emptyState!,
                  if (widget.footer != null) _buildFooter(context, colors),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridTable(BuildContext context, AppSemanticColors colors) {
    return SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: colors.surfaceMuted,
        gridLineColor: colors.borderSubtle,
        gridLineStrokeWidth: 1,
        rowHoverColor: widget.onRowClick == null ? Colors.transparent : colors.surfaceHover,
      ),
      child: SfDataGrid(
        source: _source,
        columns: _buildGridColumns(colors),
        rowHeight: widget.rowHeight,
        headerRowHeight: widget.rowHeight,
        shrinkWrapRows: true,
        frozenColumnsCount: widget.frozenColumnsCount,
        gridLinesVisibility: GridLinesVisibility.horizontal,
        headerGridLinesVisibility: GridLinesVisibility.none,
        columnWidthMode: ColumnWidthMode.fill,
        selectionMode: SelectionMode.none,
        highlightRowOnHover: widget.onRowClick != null,
        showHorizontalScrollbar: true,
        showVerticalScrollbar: false,
        onCellTap: widget.onRowClick == null
            ? null
            : (details) {
                final rowIndex = details.rowColumnIndex.rowIndex - 1;
                if (rowIndex < 0 || rowIndex >= widget.data.length || widget.loading) return;
                if (details.column.columnName == _selectionColumnName ||
                    details.column.columnName == _actionsColumnName) {
                  return;
                }
                widget.onRowClick!(widget.data[rowIndex]);
              },
        placeholder: const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildAnimatedTable(BuildContext context, AppSemanticColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAnimatedHeader(context, colors),
        if (widget.loading && widget.data.isEmpty)
          _buildAnimatedLoadingBody(context, colors)
        else
          AppDataTableAnimatedBody<T>(
            table: widget,
            buildRow: (context, item, index, {backgroundColor}) => buildAppDataTableRowContent<T>(
              context: context,
              table: widget,
              item: item,
              rowIndex: index,
              backgroundColor: backgroundColor,
            ),
          ),
      ],
    );
  }

  Widget _buildAnimatedHeader(BuildContext context, AppSemanticColors colors) {
    final cells = <Widget>[];

    if (widget.selectable) {
      cells.add(
        _buildAnimatedHeaderCell(
          context: context,
          colors: colors,
          align: TableAlign.center,
          child: const SizedBox.shrink(),
        ),
      );
    }

    for (final column in widget.columns) {
      cells.add(
        _buildAnimatedHeaderCell(
          context: context,
          colors: colors,
          align: column.align,
          child: _headerLabel(context, column, colors),
        ),
      );
    }

    if (widget.rowActions != null) {
      cells.add(
        _buildAnimatedHeaderCell(
          context: context,
          colors: colors,
          align: TableAlign.center,
          child: Semantics(label: 'Actions', child: const SizedBox.shrink()),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: SizedBox(
        height: widget.rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final cell in cells) Expanded(child: cell)],
        ),
      ),
    );
  }

  Widget _buildAnimatedHeaderCell({
    required BuildContext context,
    required AppSemanticColors colors,
    required TableAlign align,
    required Widget child,
  }) {
    return ColoredBox(
      color: colors.surfaceMuted,
      child: Container(
        alignment: switch (align) {
          TableAlign.start => Alignment.centerLeft,
          TableAlign.end => Alignment.centerRight,
          TableAlign.center => Alignment.center,
        },
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
        child: DefaultTextStyle(
          style: widget.headerTextStyle ?? AppTypography.overline(context).copyWith(color: colors.textTertiary),
          child: child,
        ),
      ),
    );
  }

  Widget _buildAnimatedLoadingBody(BuildContext context, AppSemanticColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(widget.loadingRows, (index) {
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          child: SizedBox(
            height: widget.rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.selectable)
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                      child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 16, height: 16),
                    ),
                  ),
                for (final _ in widget.columns)
                  Expanded(
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                      child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 120, height: 16),
                    ),
                  ),
                if (widget.rowActions != null) const Expanded(child: SizedBox.shrink()),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildFooter(BuildContext context, AppSemanticColors colors) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
        child: DefaultTextStyle(
          style: AppTypography.bodySm(context).copyWith(color: colors.textSecondary),
          child: widget.footer!,
        ),
      ),
    );
  }
}

class _AppDataGridSource<T> extends DataGridSource {
  _AppDataGridSource({required this.table, required this.context});

  AppDataTable<T> table;
  BuildContext context;

  AppSemanticColors get _colors => context.appColors;

  List<_GridRowData<T>> get _rowData {
    if (!table.showBodyInTable) return const [];
    if (table.loading) {
      return List.generate(table.loadingRows, (index) => _GridRowData<T>(item: null, index: index));
    }
    return table.data.asMap().entries.map((entry) => _GridRowData<T>(item: entry.value, index: entry.key)).toList();
  }

  @override
  List<DataGridRow> get rows => _rowData
      .map(
        (rowData) => DataGridRow(
          cells: [
            if (table.selectable) DataGridCell<_GridRowData<T>>(columnName: _selectionColumnName, value: rowData),
            for (final column in table.columns) DataGridCell<_GridRowData<T>>(columnName: column.id, value: rowData),
            if (table.rowActions != null) DataGridCell<_GridRowData<T>>(columnName: _actionsColumnName, value: rowData),
          ],
        ),
      )
      .toList();

  Alignment _cellAlignment(TableAlign align) => switch (align) {
    TableAlign.start => Alignment.centerLeft,
    TableAlign.end => Alignment.centerRight,
    TableAlign.center => Alignment.center,
  };

  TextAlign _textAlign(TableAlign align) => switch (align) {
    TableAlign.start => TextAlign.start,
    TableAlign.end => TextAlign.end,
    TableAlign.center => TextAlign.center,
  };

  void _toggleRow(String id) {
    final onChange = table.onSelectionChange;
    if (onChange == null) return;
    final next = Set<String>.from(table.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onChange(next);
  }

  Widget _wrapCell({
    required Widget child,
    required TableAlign align,
    Color? backgroundColor,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
  }) {
    return ColoredBox(
      color: backgroundColor ?? Colors.transparent,
      child: Container(alignment: _cellAlignment(align), padding: padding, child: child),
    );
  }

  Widget _buildSkeletonCell() {
    return _wrapCell(
      align: TableAlign.start,
      child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 120, height: 16),
    );
  }

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    final rowData = row.getCells().first.value as _GridRowData<T>;
    final item = rowData.item;
    final rowIndex = rowData.index;
    final isLoadingRow = item == null;
    final selected = !isLoadingRow && table.selectedIds.contains(table.getRowId(item as T));
    final zebraRow = table.zebra && rowIndex.isOdd;
    final rowBackground = selected ? _colors.surfaceSelected : (zebraRow ? _colors.surfaceMuted : null);

    return DataGridRowAdapter(
      color: rowBackground,
      cells: row.getCells().map((cell) {
        if (isLoadingRow) {
          if (cell.columnName == _actionsColumnName) {
            return _wrapCell(align: TableAlign.center, child: const SizedBox.shrink());
          }
          if (cell.columnName == _selectionColumnName) {
            return _wrapCell(
              align: TableAlign.center,
              child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 16, height: 16),
            );
          }
          return _buildSkeletonCell();
        }

        final rowItem = item as T;
        final id = table.getRowId(rowItem);

        if (cell.columnName == _selectionColumnName) {
          return _wrapCell(
            align: TableAlign.center,
            backgroundColor: rowBackground,
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child: appWrapMaterialInput(
                AppCheckbox(
                  value: selected ? AppCheckboxState.checked : AppCheckboxState.unchecked,
                  onChanged: table.onSelectionChange == null ? null : (_) => _toggleRow(id),
                ),
              ),
            ),
          );
        }

        if (cell.columnName == _actionsColumnName) {
          return _wrapCell(
            align: TableAlign.center,
            backgroundColor: rowBackground,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
            child: GestureDetector(
              onTap: () {},
              behavior: HitTestBehavior.opaque,
              child:
                  table.rowActions!(rowItem) ??
                  AppIconButton(
                    icon: const Icon(Icons.more_horiz, size: 16),
                    label: 'Row actions',
                    size: AppIconButtonSize.sm,
                    onPressed: () {},
                  ),
            ),
          );
        }

        final column = table.columns.firstWhere((col) => col.id == cell.columnName);
        return _wrapCell(
          align: column.align,
          backgroundColor: rowBackground,
          child: DefaultTextStyle(
            style: AppTypography.bodySm(context).copyWith(color: _colors.textPrimary),
            textAlign: _textAlign(column.align),
            child: column.accessor(rowItem),
          ),
        );
      }).toList(),
    );
  }
}
