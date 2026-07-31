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
import 'app_data_table_column_layout.dart';

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
    this.minWidth,
    this.resizable = true,
  });

  final String id;
  final String header;
  final Widget Function(T row) accessor;
  final TableAlign align;
  final bool sortable;
  final double? width;
  final double? minWidth;
  final bool resizable;
}

/// Lays out a table column cell: fixed [width], flex [fill], or default flex fill.
Widget layoutAppDataTableColumn({required Widget child, double? width, bool fill = false}) {
  if (fill) {
    return Expanded(child: child);
  }
  if (width != null) {
    return SizedBox(width: width, child: child);
  }
  return Expanded(child: child);
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
    this.rowHeightOverride,
    this.headerRowHeightOverride,
    this.resizableColumns = false,
    this.columnWidthsStorageKey,
    this.minColumnWidth = AppDataTableColumnLayout.defaultMinColumnWidth,
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
  final double? rowHeightOverride;
  final double? headerRowHeightOverride;
  final bool resizableColumns;
  final String? columnWidthsStorageKey;
  final double minColumnWidth;
  final String ariaLabel;

  double get rowHeight =>
      rowHeightOverride ??
      switch (density) {
        TableDensity.compact => 36,
        TableDensity.standard => 40,
        TableDensity.comfortable => 48,
      };

  double get headerRowHeight =>
      headerRowHeightOverride ??
      switch (density) {
        TableDensity.compact => 28,
        TableDensity.standard => 32,
        TableDensity.comfortable => 36,
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
  final Map<String, double> _columnWidths = {};
  final ScrollController _horizontalScrollController = ScrollController();
  var _lastLayoutWidth = 0.0;
  var _overflowsHorizontally = false;

  Map<String, double> get _effectiveColumnWidths => Map.unmodifiable(_columnWidths);

  bool _isFillColumn(TableColumn<T> column) {
    return widget.resizableColumns && AppDataTableColumnLayout.isFillColumn(widget.columns, column.id);
  }

  @override
  void initState() {
    super.initState();
    _source = _AppDataGridSource<T>(table: widget, context: context)
      ..columnWidths = _effectiveColumnWidths
      ..resizableColumns = widget.resizableColumns;
    if (widget.resizableColumns) {
      _loadPersistedColumnWidths();
    }
  }

  Future<void> _loadPersistedColumnWidths() async {
    final storageKey = widget.columnWidthsStorageKey;
    if (storageKey == null) {
      return;
    }

    final persisted = await AppDataTableColumnLayout.loadPersistedWidths(storageKey);
    if (!mounted || persisted == null || persisted.isEmpty) {
      return;
    }

    setState(() {
      _columnWidths
        ..clear()
        ..addAll(AppDataTableColumnLayout.pruneToColumns(widths: persisted, columns: widget.columns));
      _source.columnWidths = _effectiveColumnWidths;
    });
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _ensureColumnWidths(double availableWidth) {
    if (!widget.resizableColumns) {
      return;
    }

    final storedColumnIds = AppDataTableColumnLayout.storedColumns(widget.columns).map((column) => column.id).toSet();
    final needsInitialization = _columnWidths.isEmpty || !storedColumnIds.every(_columnWidths.containsKey);

    if (needsInitialization) {
      _columnWidths
        ..clear()
        ..addAll(
          AppDataTableColumnLayout.initialWidths(
            columns: widget.columns,
            availableWidth: availableWidth,
            selectable: widget.selectable,
            hasRowActions: widget.rowActions != null,
            persisted: _columnWidths.isEmpty ? null : _columnWidths,
            minColumnWidth: widget.minColumnWidth,
          ),
        );
      _source.columnWidths = _effectiveColumnWidths;
    }

    _lastLayoutWidth = availableWidth;
    _overflowsHorizontally =
        AppDataTableColumnLayout.minimumTableWidth(
          columns: widget.columns,
          widths: _columnWidths,
          selectable: widget.selectable,
          hasRowActions: widget.rowActions != null,
          minColumnWidth: widget.minColumnWidth,
        ) >
        availableWidth;
  }

  double? _columnWidthFor(TableColumn<T> column) {
    if (!widget.resizableColumns) {
      return column.width;
    }
    if (_isFillColumn(column) && !_overflowsHorizontally) {
      return null;
    }
    if (_isFillColumn(column)) {
      return column.minWidth ?? widget.minColumnWidth;
    }
    return _columnWidths[column.id] ?? column.width;
  }

  bool _usesFillColumnLayout(TableColumn<T> column) {
    return _isFillColumn(column) && !_overflowsHorizontally;
  }

  void _resizeColumn(String columnId, double delta) {
    if (!widget.resizableColumns || delta == 0) {
      return;
    }

    final next = AppDataTableColumnLayout.resizeColumn(
      widths: _columnWidths,
      columns: widget.columns,
      columnId: columnId,
      delta: delta,
      minColumnWidth: widget.minColumnWidth,
    );
    if (identical(next, _columnWidths)) {
      return;
    }

    setState(() {
      _columnWidths
        ..clear()
        ..addAll(next);
      _overflowsHorizontally =
          AppDataTableColumnLayout.minimumTableWidth(
            columns: widget.columns,
            widths: _columnWidths,
            selectable: widget.selectable,
            hasRowActions: widget.rowActions != null,
            minColumnWidth: widget.minColumnWidth,
          ) >
          _lastLayoutWidth;
      _source.columnWidths = _effectiveColumnWidths;
    });
  }

  Future<void> _persistColumnWidths() async {
    final storageKey = widget.columnWidthsStorageKey;
    if (!widget.resizableColumns || storageKey == null || _columnWidths.isEmpty) {
      return;
    }
    await AppDataTableColumnLayout.persistWidths(
      storageKey,
      AppDataTableColumnLayout.pruneToColumns(widths: _columnWidths, columns: widget.columns),
    );
  }

  Widget _wrapResizableWidth(Widget child, double viewportWidth) {
    if (!widget.resizableColumns) {
      return child;
    }

    if (!_overflowsHorizontally) {
      return child;
    }

    final tableWidth = AppDataTableColumnLayout.minimumTableWidth(
      columns: widget.columns,
      widths: _columnWidths,
      selectable: widget.selectable,
      hasRowActions: widget.rowActions != null,
      minColumnWidth: widget.minColumnWidth,
    );

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      notificationPredicate: (notification) => notification.depth == 0,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: tableWidth, child: child),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AppDataTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resizableColumns &&
        (oldWidget.columns != widget.columns || oldWidget.columnWidthsStorageKey != widget.columnWidthsStorageKey)) {
      _columnWidths
        ..clear()
        ..addAll(AppDataTableColumnLayout.pruneToColumns(widths: _columnWidths, columns: widget.columns));
      if (_lastLayoutWidth > 0) {
        _ensureColumnWidths(_lastLayoutWidth);
      }
    }
    _source
      ..table = widget
      ..context = context
      ..columnWidths = _effectiveColumnWidths
      ..resizableColumns = widget.resizableColumns
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
          width: widget.resizableColumns ? AppDataTableColumnLayout.selectionColumnWidth : 40,
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
      final width = _columnWidthFor(column);
      final usesFill = _usesFillColumnLayout(column);
      gridColumns.add(
        GridColumn(
          columnName: column.id,
          width: usesFill ? double.nan : (width ?? double.nan),
          columnWidthMode: usesFill ? ColumnWidthMode.fill : ColumnWidthMode.none,
          allowSorting: false,
          label: widget.resizableColumns
              ? const SizedBox.shrink()
              : Container(
                  color: colors.surfaceMuted,
                  alignment: _cellAlignment(column.align),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
                  child: _headerLabel(context, column, colors),
                ),
        ),
      );
    }

    if (widget.rowActions != null) {
      gridColumns.add(
        GridColumn(
          columnName: _actionsColumnName,
          width: AppDataTableColumnLayout.actionsColumnWidth,
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
        _ensureColumnWidths(constraints.maxWidth);

        final tableContent = Semantics(
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

        return _wrapResizableWidth(tableContent, constraints.maxWidth);
      },
    );
  }

  Widget _buildGridTable(BuildContext context, AppSemanticColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.resizableColumns) _buildTableHeaderRow(context, colors),
        SfDataGridTheme(
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
            headerRowHeight: widget.resizableColumns ? 0 : widget.headerRowHeight,
            shrinkWrapRows: true,
            frozenColumnsCount: widget.frozenColumnsCount,
            gridLinesVisibility: GridLinesVisibility.horizontal,
            headerGridLinesVisibility: GridLinesVisibility.none,
            columnWidthMode: widget.resizableColumns ? ColumnWidthMode.none : ColumnWidthMode.fill,
            selectionMode: SelectionMode.none,
            highlightRowOnHover: widget.onRowClick != null,
            showHorizontalScrollbar: !widget.resizableColumns,
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
        ),
      ],
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
              columnWidths: widget.resizableColumns ? _effectiveColumnWidths : null,
              fillColumnExpanded: widget.resizableColumns && !_overflowsHorizontally,
            ),
          ),
      ],
    );
  }

  Widget _buildAnimatedHeader(BuildContext context, AppSemanticColors colors) {
    return _buildTableHeaderRow(context, colors);
  }

  Widget _buildTableHeaderRow(BuildContext context, AppSemanticColors colors) {
    final cells = <Widget>[];

    if (widget.selectable) {
      if (widget.resizableColumns) {
        cells.add(
          SizedBox(
            width: AppDataTableColumnLayout.selectionColumnWidth,
            child: _buildAnimatedHeaderCell(
              context: context,
              colors: colors,
              align: TableAlign.center,
              child: appWrapMaterialInput(
                AppCheckbox(
                  value: _someSelected() && !_allSelected()
                      ? AppCheckboxState.indeterminate
                      : (_allSelected() ? AppCheckboxState.checked : AppCheckboxState.unchecked),
                  onChanged: widget.onSelectionChange == null ? null : (_) => _toggleAll(),
                ),
              ),
            ),
          ),
        );
      } else {
        cells.add(
          Expanded(
            child: _buildAnimatedHeaderCell(
              context: context,
              colors: colors,
              align: TableAlign.center,
              child: const SizedBox.shrink(),
            ),
          ),
        );
      }
    }

    for (final column in widget.columns) {
      cells.add(_buildHeaderColumnCell(context: context, colors: colors, column: column));
    }

    if (widget.rowActions != null) {
      cells.add(
        SizedBox(
          width: AppDataTableColumnLayout.actionsColumnWidth,
          child: _buildAnimatedHeaderCell(
            context: context,
            colors: colors,
            align: TableAlign.center,
            child: Semantics(label: 'Actions', child: const SizedBox.shrink()),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: SizedBox(
        height: widget.headerRowHeight,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells),
      ),
    );
  }

  Widget _buildHeaderColumnCell({
    required BuildContext context,
    required AppSemanticColors colors,
    required TableColumn<T> column,
  }) {
    final width = _columnWidthFor(column);
    final headerCell = _buildAnimatedHeaderCell(
      context: context,
      colors: colors,
      align: column.align,
      child: _headerLabel(context, column, colors),
    );

    if (!widget.resizableColumns) {
      return layoutAppDataTableColumn(width: width, child: headerCell);
    }

    if (_usesFillColumnLayout(column)) {
      return Expanded(child: headerCell);
    }

    return SizedBox(
      width: width,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          headerCell,
          if (column.resizable)
            Positioned(
              right: -AppDataTableColumnLayout.resizeHandleWidth / 2,
              top: 0,
              bottom: 0,
              width: AppDataTableColumnLayout.resizeHandleWidth,
              child: _AppDataTableColumnResizeHandle(
                colors: colors,
                onDrag: (delta) => _resizeColumn(column.id, delta),
                onDragEnd: _persistColumnWidths,
              ),
            ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3, vertical: AppSpacing.space2),
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
                  widget.resizableColumns
                      ? SizedBox(
                          width: AppDataTableColumnLayout.selectionColumnWidth,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                            child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 16, height: 16),
                          ),
                        )
                      : Expanded(
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                            child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 16, height: 16),
                          ),
                        ),
                for (final column in widget.columns)
                  layoutAppDataTableColumn(
                    width: _columnWidthFor(column),
                    fill: _usesFillColumnLayout(column),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                      child: AppSkeleton(
                        variant: SkeletonVariant.rectangular,
                        width: () {
                          final width = _columnWidthFor(column);
                          if (width != null) {
                            return (width - AppSpacing.space3 * 2).clamp(48.0, 120.0);
                          }
                          return 120.0;
                        }(),
                        height: 16,
                      ),
                    ),
                  ),
                if (widget.rowActions != null) const SizedBox(width: AppDataTableColumnLayout.actionsColumnWidth),
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

class _AppDataTableColumnResizeHandle extends StatefulWidget {
  const _AppDataTableColumnResizeHandle({required this.colors, required this.onDrag, required this.onDragEnd});

  final AppSemanticColors colors;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;

  @override
  State<_AppDataTableColumnResizeHandle> createState() => _AppDataTableColumnResizeHandleState();
}

class _AppDataTableColumnResizeHandleState extends State<_AppDataTableColumnResizeHandle> {
  var _dragging = false;
  var _hovered = false;

  void _handlePointerDown(PointerDownEvent event) {
    if (!mounted) {
      return;
    }
    setState(() => _dragging = true);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_dragging) {
      return;
    }
    widget.onDrag(event.delta.dx);
  }

  void _handlePointerEnd() {
    if (!_dragging) {
      return;
    }
    if (mounted) {
      setState(() => _dragging = false);
    } else {
      _dragging = false;
    }
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    final color = _dragging || _hovered ? widget.colors.actionPrimary : widget.colors.borderDefault;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _handlePointerEnd(),
      onPointerCancel: (_) => _handlePointerEnd(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) {
          if (mounted) {
            setState(() => _hovered = true);
          }
        },
        onExit: (_) {
          if (mounted) {
            setState(() => _hovered = false);
          }
        },
        child: Semantics(
          label: 'Resize column',
          child: Align(
            alignment: Alignment.center,
            child: AnimatedContainer(duration: const Duration(milliseconds: 120), width: 2, color: color),
          ),
        ),
      ),
    );
  }
}

class _AppDataGridSource<T> extends DataGridSource {
  _AppDataGridSource({required this.table, required this.context});

  AppDataTable<T> table;
  BuildContext context;
  Map<String, double> columnWidths = {};
  bool resizableColumns = false;

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
