import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/components/app_skeleton.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_radius.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

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

/// Data grid built on Material [Table] (web `DataTable`).
class AppDataTable<T> extends StatelessWidget {
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
  final String ariaLabel;

  double get _rowHeight => switch (density) {
    TableDensity.compact => 36,
    TableDensity.standard => 40,
    TableDensity.comfortable => 48,
  };

  bool _allSelected() => data.isNotEmpty && data.every((row) => selectedIds.contains(getRowId(row)));

  bool _someSelected() => data.any((row) => selectedIds.contains(getRowId(row)));

  void _toggleAll() {
    final onChange = onSelectionChange;
    if (onChange == null) return;
    if (_allSelected()) {
      onChange({});
    } else {
      onChange(data.map(getRowId).toSet());
    }
  }

  void _toggleRow(String id) {
    final onChange = onSelectionChange;
    if (onChange == null) return;
    final next = Set<String>.from(selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onChange(next);
  }

  Map<int, TableColumnWidth> _columnWidths() {
    final widths = <int, TableColumnWidth>{};
    var index = 0;
    if (selectable) {
      widths[index++] = const FixedColumnWidth(40);
    }
    for (final column in columns) {
      widths[index++] = column.width != null ? FixedColumnWidth(column.width!) : const FlexColumnWidth(1);
    }
    if (rowActions != null) {
      widths[index] = const FixedColumnWidth(48);
    }
    return widths;
  }

  AlignmentDirectional _cellAlignment(TableAlign align) => switch (align) {
    TableAlign.start => AlignmentDirectional.centerStart,
    TableAlign.end => AlignmentDirectional.centerEnd,
    TableAlign.center => AlignmentDirectional.center,
  };

  TextAlign _textAlign(TableAlign align) => switch (align) {
    TableAlign.start => TextAlign.start,
    TableAlign.end => TextAlign.end,
    TableAlign.center => TextAlign.center,
  };

  Widget _buildSortIcon(String columnId, AppSemanticColors colors) {
    if (sortColumn != columnId) {
      return Icon(Icons.swap_vert, size: 14, color: colors.iconMuted);
    }
    return Icon(
      sortDirection == SortDirection.asc ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: colors.textLink,
    );
  }

  Widget _buildHeaderCell(BuildContext context, TableColumn<T> column, int columnIndex, AppSemanticColors colors) {
    final align = column.align;
    final sticky = stickyFirstColumn && columnIndex == 0;
    final headerStyle = AppTypography.overline(context).copyWith(color: colors.textTertiary);
    final headerContentAlignment = switch (align) {
      TableAlign.start => AlignmentDirectional.centerStart,
      TableAlign.end => AlignmentDirectional.centerEnd,
      TableAlign.center => AlignmentDirectional.center,
    };

    Widget label;
    if (column.sortable) {
      final sortState = sortColumn == column.id
          ? (sortDirection == SortDirection.asc ? 'ascending' : 'descending')
          : 'none';
      label = Semantics(
        label: '${column.header}, sort $sortState',
        button: true,
        child: SizedBox(
          height: _rowHeight,
          width: double.infinity,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: colors.textTertiary,
              alignment: headerContentAlignment,
            ),
            onPressed: onSort == null ? null : () => onSort!(column.id),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(column.header, style: headerStyle),
                const SizedBox(width: AppSpacing.space1),
                _buildSortIcon(column.id, colors),
              ],
            ),
          ),
        ),
      );
    } else {
      label = Text(column.header, style: headerStyle, textAlign: _textAlign(align));
    }

    return _wrapCell(
      alignment: _cellAlignment(align),
      backgroundColor: sticky ? colors.surfaceMuted : colors.surfaceMuted,
      height: _rowHeight,
      padding: column.sortable ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
      child: column.sortable ? label : SizedBox(width: double.infinity, child: label),
    );
  }

  TableRow _buildHeaderTableRow(BuildContext context, AppSemanticColors colors) {
    final cells = <Widget>[];

    if (selectable) {
      final checkboxState = _someSelected() && !_allSelected()
          ? AppCheckboxState.indeterminate
          : (_allSelected() ? AppCheckboxState.checked : AppCheckboxState.unchecked);
      cells.add(
        _wrapCell(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
          child: appWrapMaterialInput(
            AppCheckbox(value: checkboxState, onChanged: onSelectionChange == null ? null : (_) => _toggleAll()),
          ),
        ),
      );
    }

    for (var i = 0; i < columns.length; i++) {
      cells.add(_buildHeaderCell(context, columns[i], i, colors));
    }

    if (rowActions != null) {
      cells.add(
        _wrapCell(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
          child: Semantics(label: 'Actions', child: const SizedBox.shrink()),
        ),
      );
    }

    return TableRow(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      children: cells,
    );
  }

  Widget _buildDataCell({
    required BuildContext context,
    required Widget child,
    required TableAlign align,
    required int columnIndex,
    required bool selected,
    required AppSemanticColors colors,
  }) {
    final sticky = stickyFirstColumn && columnIndex == 0;
    return _wrapCell(
      alignment: _cellAlignment(align),
      backgroundColor: sticky ? (selected ? colors.surfaceSelected : colors.surfaceDefault) : null,
      height: _rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
      child: DefaultTextStyle(
        style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
        textAlign: _textAlign(align),
        child: child,
      ),
    );
  }

  List<TableRow> _buildDataRows(BuildContext context, AppSemanticColors colors) {
    return [
      for (var rowIndex = 0; rowIndex < data.length; rowIndex++)
        _buildDataRow(context, data[rowIndex], rowIndex, colors),
    ];
  }

  TableRow _buildDataRow(BuildContext context, T row, int rowIndex, AppSemanticColors colors) {
    final id = getRowId(row);
    final selected = selectedIds.contains(id);
    final zebraRow = zebra && rowIndex.isOdd;
    final interactive = onRowClick != null;

    final rowBackground = selected ? colors.surfaceSelected : (zebraRow ? colors.surfaceMuted : null);

    final cells = <Widget>[];

    if (selectable) {
      cells.add(
        _wrapCell(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: appWrapMaterialInput(
              AppCheckbox(
                value: selected ? AppCheckboxState.checked : AppCheckboxState.unchecked,
                onChanged: onSelectionChange == null ? null : (_) => _toggleRow(id),
              ),
            ),
          ),
        ),
      );
    }

    for (var i = 0; i < columns.length; i++) {
      final column = columns[i];
      cells.add(
        _buildDataCell(
          context: context,
          child: column.accessor(row),
          align: column.align,
          columnIndex: i,
          selected: selected,
          colors: colors,
        ),
      );
    }

    if (rowActions != null) {
      cells.add(
        _wrapCell(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child:
                rowActions!(row) ??
                AppIconButton(
                  icon: const Icon(Icons.more_horiz, size: 16),
                  label: 'Row actions',
                  size: AppIconButtonSize.sm,
                  onPressed: () {},
                ),
          ),
        ),
      );
    }

    return TableRow(
      decoration: BoxDecoration(
        color: rowBackground,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      children: cells.map((cell) {
        if (!interactive) return cell;
        return _InteractiveRowCell(onActivate: () => onRowClick!(row), hoverColor: colors.surfaceHover, child: cell);
      }).toList(),
    );
  }

  List<TableRow> _buildSkeletonRows(AppSemanticColors colors) {
    return [
      for (var i = 0; i < loadingRows; i++)
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderSubtle)),
          ),
          children: [
            if (selectable)
              _wrapCell(
                height: _rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 16, height: 16),
              ),
            for (final _ in columns)
              _wrapCell(
                height: _rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
                child: const AppSkeleton(variant: SkeletonVariant.rectangular, width: 120, height: 16),
              ),
            if (rowActions != null)
              _wrapCell(
                height: _rowHeight,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
                child: const SizedBox.shrink(),
              ),
          ],
        ),
    ];
  }

  bool get _showBodyInTable => loading || (errorState == null && !(data.isEmpty && emptyState != null));

  Widget _buildTable(BuildContext context, AppSemanticColors colors, double minWidth) {
    final rows = <TableRow>[
      _buildHeaderTableRow(context, colors),
      if (loading) ..._buildSkeletonRows(colors),
      if (!loading && _showBodyInTable) ..._buildDataRows(context, colors),
    ];

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Table(
        columnWidths: _columnWidths(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: rows,
      ),
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
          child: footer!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          container: true,
          label: ariaLabel,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceDefault,
              border: Border.all(color: colors.borderDefault),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildTable(context, colors, constraints.maxWidth),
                  ),
                  if (!loading && errorState != null)
                    errorState!
                  else if (!loading && data.isEmpty && emptyState != null)
                    emptyState!,
                  if (footer != null) _buildFooter(context, colors),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _wrapCell({
  required Widget child,
  required double height,
  EdgeInsetsGeometry? padding,
  AlignmentDirectional alignment = AlignmentDirectional.centerStart,
  Color? backgroundColor,
}) {
  return TableCell(
    verticalAlignment: TableCellVerticalAlignment.middle,
    child: ColoredBox(
      color: backgroundColor ?? Colors.transparent,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Align(alignment: alignment, widthFactor: 1, child: child),
        ),
      ),
    ),
  );
}

class _InteractiveRowCell extends StatefulWidget {
  const _InteractiveRowCell({required this.child, required this.onActivate, required this.hoverColor});

  final Widget child;
  final VoidCallback onActivate;
  final Color hoverColor;

  @override
  State<_InteractiveRowCell> createState() => _InteractiveRowCellState();
}

class _InteractiveRowCellState extends State<_InteractiveRowCell> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onActivate,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standardCurve,
          color: _hovered ? widget.hoverColor : Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}
