import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_clinic/core/ui/foundation.dart';
import 'package:ai_clinic/core/ui/widgets/actions/app_icon_button.dart';
import 'package:ai_clinic/core/ui/widgets/display/app_skeleton.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_empty_state.dart';
import 'package:ai_clinic/core/ui/widgets/feedback/app_error_state.dart';
import 'package:ai_clinic/core/ui/widgets/inputs/app_checkbox.dart';
import 'package:ai_clinic/core/ui/widgets/layout/app_card.dart';

/// Horizontal alignment for [AppTableColumn] cells and headers.
enum AppTableColumnAlign { start, center, end }

/// Active sort direction for a controlled [AppTable] column.
enum AppTableSortDirection { ascending, descending }

/// Row height density for [AppTable].
enum AppTableDensity {
  compact(36),
  standard(40),
  comfortable(54);

  const AppTableDensity(this.rowHeight);

  final double rowHeight;

  /// Maps shell [AppDensity] to table row density.
  static AppTableDensity fromShellDensity(AppDensity density) => switch (density) {
    AppDensity.compact => AppTableDensity.compact,
    AppDensity.standard => AppTableDensity.standard,
    AppDensity.comfortable => AppTableDensity.comfortable,
  };
}

/// Describes a single column in [AppTable].
@immutable
class AppTableColumn<T> {
  const AppTableColumn({
    required this.id,
    required this.header,
    required this.cellBuilder,
    this.align = AppTableColumnAlign.start,
    this.sortable = false,
    this.width,
    this.flex,
    this.sticky = false,
  });

  final String id;
  final String header;
  final Widget Function(BuildContext context, T row) cellBuilder;
  final AppTableColumnAlign align;
  final bool sortable;
  final double? width;
  final int? flex;
  final bool sticky;
}

/// Convenience bundle for table data and display flags.
@immutable
class AppTableDataState<T> {
  const AppTableDataState({this.data = const [], this.loading = false, this.error, this.filteredEmpty = false});

  final List<T> data;
  final bool loading;
  final Object? error;
  final bool filteredEmpty;
}

/// Signature for controlled sort changes (`null` clears sort).
typedef AppTableSortChanged = void Function(String? columnId, AppTableSortDirection? direction);

/// Signature for controlled row selection changes.
typedef AppTableSelectionChanged = void Function(Set<String> selectedIds);

/// Core data grid for patients, invoices, appointments, and catalogs.
///
/// Supports sticky header, optional sticky first column, row virtualization,
/// sorting, selection, density, and a stacked row-card layout on narrow widths.
class AppTable<T> extends StatefulWidget {
  const AppTable({
    required this.columns,
    required this.rowId,
    this.data = const [],
    this.tableState,
    this.density = AppTableDensity.comfortable,
    this.shellDensity,
    this.zebra = false,
    this.stickyFirstColumn = false,
    this.selectable = false,
    this.selectedIds = const {},
    this.onSelectionChanged,
    this.sortColumnId,
    this.sortDirection,
    this.onSortChanged,
    this.loading = false,
    this.loadingRows = 5,
    this.error,
    this.onRetry,
    this.errorMessage,
    this.filteredEmpty = false,
    this.emptyState,
    this.filteredEmptyState,
    this.errorState,
    this.footer,
    this.onRowTap,
    this.rowActions,
    this.semanticLabel,
    this.scrollController,
    super.key,
  });

  final List<AppTableColumn<T>> columns;
  final String Function(T row) rowId;
  final List<T> data;
  final AppTableDataState<T>? tableState;
  final AppTableDensity density;
  final AppDensity? shellDensity;
  final bool zebra;
  final bool stickyFirstColumn;
  final bool selectable;
  final Set<String> selectedIds;
  final AppTableSelectionChanged? onSelectionChanged;
  final String? sortColumnId;
  final AppTableSortDirection? sortDirection;
  final AppTableSortChanged? onSortChanged;
  final bool loading;
  final int loadingRows;
  final Object? error;
  final VoidCallback? onRetry;
  final String? errorMessage;
  final bool filteredEmpty;
  final Widget? emptyState;
  final Widget? filteredEmptyState;
  final Widget? errorState;
  final Widget? footer;
  final ValueChanged<T>? onRowTap;
  final Widget? Function(T row)? rowActions;
  final String? semanticLabel;
  final ScrollController? scrollController;

  @override
  State<AppTable<T>> createState() => _AppTableState<T>();
}

class _AppTableState<T> extends State<AppTable<T>> {
  static const double _selectionColumnWidth = AppSpacing.s10;
  static const double _actionsColumnWidth = AppSpacing.s12;
  static const double _defaultColumnWidth = 120;
  static const double _horizontalCellPadding = AppSpacing.s3;
  static const double _verticalCellPadding = AppSpacing.s2;

  late final ScrollController _verticalController;
  ScrollController? _stickyVerticalController;
  final ScrollController _horizontalController = ScrollController();
  bool _syncingVertical = false;
  int _focusedRowIndex = -1;
  final Map<int, FocusNode> _rowFocusNodes = {};

  List<T> get _data => widget.tableState?.data ?? widget.data;
  bool get _loading => widget.tableState?.loading ?? widget.loading;
  Object? get _error => widget.tableState?.error ?? widget.error;
  bool get _filteredEmpty => widget.tableState?.filteredEmpty ?? widget.filteredEmpty;

  AppTableDensity get _density {
    if (widget.shellDensity != null) {
      return AppTableDensity.fromShellDensity(widget.shellDensity!);
    }
    return widget.density;
  }

  bool get _hasRowActions => widget.rowActions != null;

  int? get _stickyColumnIndex {
    if (!widget.stickyFirstColumn) return null;
    final stickyIndex = widget.columns.indexWhere((c) => c.sticky);
    return stickyIndex >= 0 ? stickyIndex : 0;
  }

  @override
  void initState() {
    super.initState();
    _verticalController = widget.scrollController ?? ScrollController();
    if (_stickyColumnIndex != null) {
      _stickyVerticalController = ScrollController();
      _verticalController.addListener(_syncFromPrimaryVertical);
      _stickyVerticalController!.addListener(_syncFromStickyVertical);
    }
  }

  @override
  void didUpdateWidget(covariant AppTable<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hadSticky = oldWidget.stickyFirstColumn || oldWidget.columns.any((c) => c.sticky);
    final hasSticky = widget.stickyFirstColumn || widget.columns.any((c) => c.sticky);

    if (hadSticky != hasSticky) {
      _stickyVerticalController?.removeListener(_syncFromStickyVertical);
      _verticalController.removeListener(_syncFromPrimaryVertical);
      _stickyVerticalController?.dispose();
      _stickyVerticalController = hasSticky ? ScrollController() : null;
      if (_stickyVerticalController != null) {
        _verticalController.addListener(_syncFromPrimaryVertical);
        _stickyVerticalController!.addListener(_syncFromStickyVertical);
      }
    }

    if (oldWidget.scrollController != widget.scrollController) {
      if (oldWidget.scrollController == null) {
        _verticalController.dispose();
      }
      _verticalController = widget.scrollController ?? ScrollController();
    }

    _pruneFocusNodes(_data.length);
  }

  @override
  void dispose() {
    _verticalController.removeListener(_syncFromPrimaryVertical);
    _stickyVerticalController?.removeListener(_syncFromStickyVertical);
    if (widget.scrollController == null) {
      _verticalController.dispose();
    }
    _stickyVerticalController?.dispose();
    _horizontalController.dispose();
    for (final node in _rowFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFromPrimaryVertical() => _syncVertical(source: _verticalController, target: _stickyVerticalController);

  void _syncFromStickyVertical() => _syncVertical(source: _stickyVerticalController!, target: _verticalController);

  void _syncVertical({required ScrollController source, required ScrollController? target}) {
    if (_syncingVertical || target == null) return;
    if (!source.hasClients || !target.hasClients) return;
    _syncingVertical = true;
    target.jumpTo(source.offset);
    _syncingVertical = false;
  }

  void _pruneFocusNodes(int rowCount) {
    final staleKeys = _rowFocusNodes.keys.where((index) => index >= rowCount).toList();
    for (final key in staleKeys) {
      _rowFocusNodes.remove(key)?.dispose();
    }
  }

  FocusNode _focusNodeForRow(int index) {
    return _rowFocusNodes.putIfAbsent(index, FocusNode.new);
  }

  bool get _allSelected => _data.isNotEmpty && _data.every((row) => widget.selectedIds.contains(widget.rowId(row)));

  bool get _someSelected => _data.any((row) => widget.selectedIds.contains(widget.rowId(row)));

  void _toggleAll() {
    final onChanged = widget.onSelectionChanged;
    if (onChanged == null) return;
    if (_allSelected) {
      onChanged({});
    } else {
      onChanged(_data.map(widget.rowId).toSet());
    }
  }

  void _toggleRow(String id) {
    final onChanged = widget.onSelectionChanged;
    if (onChanged == null) return;
    final next = Set<String>.from(widget.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onChanged(next);
  }

  void _handleSort(String columnId) {
    final onSort = widget.onSortChanged;
    if (onSort == null) return;

    final currentId = widget.sortColumnId;
    final currentDir = widget.sortDirection;

    if (currentId != columnId) {
      onSort(columnId, AppTableSortDirection.ascending);
      return;
    }

    if (currentDir == null) {
      onSort(columnId, AppTableSortDirection.ascending);
    } else if (currentDir == AppTableSortDirection.ascending) {
      onSort(columnId, AppTableSortDirection.descending);
    } else {
      onSort(null, null);
    }
  }

  void _moveRowFocus(int delta) {
    if (_data.isEmpty) return;
    final next = (_focusedRowIndex + delta).clamp(0, _data.length - 1);
    setState(() => _focusedRowIndex = next);
    _focusNodeForRow(next).requestFocus();
  }

  double _columnWidth(AppTableColumn<T> column, double viewportWidth) {
    if (column.width != null) return column.width!;
    final flexColumns = widget.columns.where((c) => c.flex != null).toList();
    if (column.flex != null && flexColumns.isNotEmpty) {
      final flexTotal = flexColumns.fold<int>(0, (sum, c) => sum + c.flex!);
      final fixedTotal = widget.columns.where((c) => c.width != null).fold<double>(0, (sum, c) => sum + c.width!);
      final flexSpace = (viewportWidth - fixedTotal).clamp(0, double.infinity);
      return flexSpace * column.flex! / flexTotal;
    }
    return _defaultColumnWidth;
  }

  double _tableMinWidth(double viewportWidth) {
    var width = 0.0;
    if (widget.selectable) width += _selectionColumnWidth;
    for (final column in widget.columns) {
      width += _columnWidth(column, viewportWidth);
    }
    if (_hasRowActions) width += _actionsColumnWidth;
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      container: true,
      label: widget.semanticLabel ?? 'Data table',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderDefault),
          borderRadius: AppRadii.lgAll,
        ),
        child: ClipRRect(
          borderRadius: AppRadii.lgAll,
          child: LayoutBuilder(
            builder: (context, constraints) {
              assert(() {
                if (widget.stickyFirstColumn && !constraints.maxHeight.isFinite) {
                  debugPrint(
                    'AppTable: stickyFirstColumn requires a bounded max height. '
                    'Wrap the table in Expanded or a SizedBox with a fixed height.',
                  );
                }
                return true;
              }());
              final useStackedLayout = constraints.maxWidth < AppBreakpoints.sm;
              if (useStackedLayout) {
                return _buildStackedLayout(context);
              }
              return _buildGridLayout(context, constraints.maxWidth, maxHeight: constraints.maxHeight);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStackedLayout(BuildContext context) {
    if (_loading) {
      return _buildStackedSkeleton(context);
    }
    if (_error != null) {
      return _buildErrorState(context);
    }
    if (_data.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.separated(
      controller: widget.scrollController,
      shrinkWrap: widget.scrollController == null,
      padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
      itemCount: _data.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s3),
      itemBuilder: (context, index) => _buildStackedRowCard(context, _data[index], index),
    );
  }

  Widget _buildStackedSkeleton(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.all(AppSpacing.s3),
      itemCount: widget.loadingRows,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s3),
      itemBuilder: (context, index) {
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.columns.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.s3),
                const AppSkeleton(height: AppSpacing.s4),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildStackedRowCard(BuildContext context, T row, int index) {
    final colors = context.colors;
    final id = widget.rowId(row);
    final selected = widget.selectedIds.contains(id);
    final interactive = widget.onRowTap != null;

    Widget card = AppCard(
      variant: interactive ? AppCardVariant.interactive : AppCardVariant.flat,
      onTap: interactive ? () => widget.onRowTap!(row) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.selectable || _hasRowActions)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.s3),
              child: Row(
                children: [
                  if (widget.selectable)
                    AppCheckbox(value: selected, onChanged: (_) => _toggleRow(id), semanticLabel: 'Select row $id'),
                  const Spacer(),
                  if (_hasRowActions)
                    _buildRowActions(context, row) ??
                        AppIconButton(
                          icon: LucideIcons.moreHorizontal,
                          semanticLabel: 'Row actions',
                          size: AppIconButtonSize.sm,
                          onPressed: () {},
                        ),
                ],
              ),
            ),
          for (var i = 0; i < widget.columns.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s3),
            _StackedField(
              label: widget.columns[i].header,
              value: widget.columns[i].cellBuilder(context, row),
              align: widget.columns[i].align,
            ),
          ],
        ],
      ),
    );

    if (selected) {
      card = DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceSelected, borderRadius: AppRadii.lgAll),
        child: card,
      );
    }

    if (interactive) {
      card = Focus(
        focusNode: _focusNodeForRow(index),
        onKeyEvent: (node, event) => _handleRowKeyEvent(node, event, row),
        child: AppFocusRing(visible: _focusNodeForRow(index).hasFocus, borderRadius: AppRadii.lgAll, child: card),
      );
    }

    return Semantics(selected: widget.selectable ? selected : null, child: card);
  }

  KeyEventResult _handleRowKeyEvent(FocusNode node, KeyEvent event, T row) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onRowTap?.call(row);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveRowFocus(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveRowFocus(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildGridLayout(BuildContext context, double viewportWidth, {required double maxHeight}) {
    final stickyIndex = _stickyColumnIndex;
    if (stickyIndex != null) {
      return _buildSplitStickyGrid(context, viewportWidth, stickyIndex, maxHeight: maxHeight);
    }
    return _buildUnifiedGrid(context, viewportWidth, maxHeight: maxHeight);
  }

  Widget _buildUnifiedGrid(BuildContext context, double viewportWidth, {required double maxHeight}) {
    final minWidth = _tableMinWidth(viewportWidth).clamp(viewportWidth, double.infinity);
    final boundedHeight = maxHeight.isFinite;

    return Scrollbar(
      controller: _horizontalController,
      thumbVisibility: minWidth > viewportWidth,
      notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: minWidth,
          height: boundedHeight ? maxHeight : null,
          child: _buildVerticalScroll(
            context: context,
            viewportWidth: viewportWidth,
            maxHeight: boundedHeight ? maxHeight : null,
            header: _buildHeaderRow(
              context,
              viewportWidth,
              columns: widget.columns,
              includeSelection: widget.selectable,
              includeActions: _hasRowActions,
            ),
            bodySliver: _buildBodySliver(context, viewportWidth, columnSlice: null),
          ),
        ),
      ),
    );
  }

  Widget _buildSplitStickyGrid(
    BuildContext context,
    double viewportWidth,
    int stickyIndex, {
    required double maxHeight,
  }) {
    final stickyColumn = widget.columns[stickyIndex];
    final scrollColumns = [
      for (var i = 0; i < widget.columns.length; i++)
        if (i != stickyIndex) widget.columns[i],
    ];

    final stickyWidth = _columnWidth(stickyColumn, viewportWidth) + (widget.selectable ? _selectionColumnWidth : 0);
    final scrollMinWidth =
        scrollColumns.map((c) => _columnWidth(c, viewportWidth)).fold<double>(0, (a, b) => a + b) +
        (_hasRowActions ? _actionsColumnWidth : 0);

    final boundedHeight = maxHeight.isFinite;

    Widget buildGridRow(double? bodyHeight) {
      final rowHeight = bodyHeight != null && bodyHeight.isFinite ? bodyHeight : null;

      return Row(
        crossAxisAlignment: rowHeight != null ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: stickyWidth,
            child: _buildVerticalScroll(
              context: context,
              viewportWidth: viewportWidth,
              controller: _stickyVerticalController,
              maxHeight: rowHeight,
              header: _buildHeaderRow(
                context,
                viewportWidth,
                columns: [stickyColumn],
                includeSelection: widget.selectable,
                includeActions: false,
              ),
              bodySliver: _buildBodySliver(
                context,
                viewportWidth,
                columnSlice: _StickySlice(mode: _StickySliceMode.onlySticky, stickyIndex: stickyIndex),
              ),
              includeFooter: false,
            ),
          ),
          Expanded(
            child: rowHeight == null
                ? Scrollbar(
                    controller: _horizontalController,
                    thumbVisibility: scrollMinWidth > (viewportWidth - stickyWidth),
                    notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _horizontalController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollMinWidth.clamp(viewportWidth - stickyWidth, double.infinity),
                        child: _buildVerticalScroll(
                          context: context,
                          viewportWidth: viewportWidth,
                          header: _buildHeaderRow(
                            context,
                            viewportWidth,
                            columns: scrollColumns,
                            includeSelection: false,
                            includeActions: _hasRowActions,
                          ),
                          bodySliver: _buildBodySliver(
                            context,
                            viewportWidth,
                            columnSlice: _StickySlice(mode: _StickySliceMode.withoutSticky, stickyIndex: stickyIndex),
                          ),
                          includeFooter: false,
                        ),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final scrollBodyHeight = constraints.maxHeight;
                      return Scrollbar(
                        controller: _horizontalController,
                        thumbVisibility: scrollMinWidth > (viewportWidth - stickyWidth),
                        notificationPredicate: (notification) => notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: scrollMinWidth.clamp(viewportWidth - stickyWidth, double.infinity),
                            height: scrollBodyHeight,
                            child: _buildVerticalScroll(
                              context: context,
                              viewportWidth: viewportWidth,
                              maxHeight: scrollBodyHeight,
                              header: _buildHeaderRow(
                                context,
                                viewportWidth,
                                columns: scrollColumns,
                                includeSelection: false,
                                includeActions: _hasRowActions,
                              ),
                              bodySliver: _buildBodySliver(
                                context,
                                viewportWidth,
                                columnSlice: _StickySlice(
                                  mode: _StickySliceMode.withoutSticky,
                                  stickyIndex: stickyIndex,
                                ),
                              ),
                              includeFooter: false,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    if (!boundedHeight) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [buildGridRow(null), if (widget.footer != null) _buildFooter(context, viewportWidth)],
      );
    }

    return SizedBox(
      height: maxHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: LayoutBuilder(builder: (context, constraints) => buildGridRow(constraints.maxHeight))),
          if (widget.footer != null) _buildFooter(context, viewportWidth),
        ],
      ),
    );
  }

  Widget _buildVerticalScroll({
    required BuildContext context,
    required double viewportWidth,
    required Widget bodySliver,
    required Widget header,
    ScrollController? controller,
    bool includeFooter = true,
    double? maxHeight,
  }) {
    final bounded = maxHeight != null && maxHeight.isFinite;

    final scrollView = CustomScrollView(
      controller: controller ?? _verticalController,
      shrinkWrap: !bounded && widget.scrollController == null,
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _TableHeaderDelegate(rowHeight: _density.rowHeight, child: header),
        ),
        bodySliver,
        if (includeFooter && widget.footer != null) SliverToBoxAdapter(child: _buildFooter(context, viewportWidth)),
      ],
    );

    if (bounded) {
      return SizedBox(height: maxHeight, child: scrollView);
    }
    return scrollView;
  }

  Widget _buildHeaderRow(
    BuildContext context,
    double viewportWidth, {
    required List<AppTableColumn<T>> columns,
    required bool includeSelection,
    required bool includeActions,
  }) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: SizedBox(
        height: _density.rowHeight,
        child: Row(
          children: [
            if (includeSelection)
              SizedBox(
                width: _selectionColumnWidth,
                child: Center(
                  child: AppCheckbox(
                    tristate: true,
                    value: _allSelected
                        ? true
                        : _someSelected
                        ? null
                        : false,
                    onChanged: widget.onSelectionChanged == null ? null : (_) => _toggleAll(),
                    semanticLabel: 'Select all rows',
                  ),
                ),
              ),
            for (final column in columns) _buildHeaderCell(context, column, viewportWidth),
            if (includeActions)
              SizedBox(
                width: _actionsColumnWidth,
                child: Semantics(label: 'Actions', child: const SizedBox.shrink()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, AppTableColumn<T> column, double viewportWidth) {
    final colors = context.colors;
    final typography = context.typography;
    final width = _columnWidth(column, viewportWidth);
    final align = _alignmentFor(column.align);

    Widget label = Text(
      column.header,
      style: typography.overline.copyWith(color: colors.textTertiary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (column.sortable && widget.onSortChanged != null) {
      final isActive = widget.sortColumnId == column.id;
      final direction = widget.sortDirection;
      final icon = !isActive || direction == null
          ? LucideIcons.chevronsUpDown
          : direction == AppTableSortDirection.ascending
          ? LucideIcons.chevronUp
          : LucideIcons.chevronDown;

      label = AppPressable.builder(
        onTap: () => _handleSort(column.id),
        borderRadius: AppRadii.smAll,
        semanticLabel: 'Sort by ${column.header}',
        builder: (context, states, _) {
          final hovered = states.contains(WidgetState.hovered);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  column.header,
                  style: typography.overline.copyWith(
                    color: hovered || isActive ? colors.textPrimary : colors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.s1),
              AppIcon(
                icon: icon,
                dimension: AppSpacing.s3 + AppSpacing.s0_5,
                color: isActive ? colors.textLink : colors.iconMuted,
              ),
            ],
          );
        },
      );
    }

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _horizontalCellPadding,
          vertical: _verticalCellPadding,
        ),
        child: Align(alignment: align, child: label),
      ),
    );
  }

  Widget _buildBodySliver(BuildContext context, double viewportWidth, {required _StickySlice? columnSlice}) {
    if (_loading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildSkeletonRow(context, viewportWidth, columnSlice: columnSlice),
          childCount: widget.loadingRows,
        ),
      );
    }

    if (_error != null) {
      return SliverFillRemaining(hasScrollBody: false, child: _buildErrorState(context));
    }

    if (_data.isEmpty) {
      return SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState(context));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildDataRow(context, _data[index], index, viewportWidth, columnSlice: columnSlice),
        childCount: _data.length,
      ),
    );
  }

  List<AppTableColumn<T>> _columnsForSlice(_StickySlice? slice) {
    if (slice == null) return widget.columns;
    if (slice.mode == _StickySliceMode.onlySticky) {
      return [widget.columns[slice.stickyIndex]];
    }
    return [
      for (var i = 0; i < widget.columns.length; i++)
        if (i != slice.stickyIndex) widget.columns[i],
    ];
  }

  bool _includeSelectionForSlice(_StickySlice? slice) {
    if (slice == null) return widget.selectable;
    return slice.mode == _StickySliceMode.onlySticky && widget.selectable;
  }

  bool _includeActionsForSlice(_StickySlice? slice) {
    if (slice == null) return _hasRowActions;
    return slice.mode != _StickySliceMode.onlySticky && _hasRowActions;
  }

  Widget _buildSkeletonRow(BuildContext context, double viewportWidth, {required _StickySlice? columnSlice}) {
    final colors = context.colors;
    final columns = _columnsForSlice(columnSlice);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: SizedBox(
        height: _density.rowHeight,
        child: Row(
          children: [
            if (_includeSelectionForSlice(columnSlice))
              SizedBox(
                width: _selectionColumnWidth,
                child: const Center(
                  child: AppSkeleton(shape: AppSkeletonShape.rectangular, width: AppSpacing.s4, height: AppSpacing.s4),
                ),
              ),
            for (final column in columns)
              SizedBox(
                width: _columnWidth(column, viewportWidth),
                child: const Padding(
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: _horizontalCellPadding,
                    vertical: _verticalCellPadding,
                  ),
                  child: AppSkeleton(width: 120, height: AppSpacing.s4),
                ),
              ),
            if (_includeActionsForSlice(columnSlice)) const SizedBox(width: _actionsColumnWidth),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(
    BuildContext context,
    T row,
    int index,
    double viewportWidth, {
    required _StickySlice? columnSlice,
  }) {
    final colors = context.colors;
    final id = widget.rowId(row);
    final selected = widget.selectedIds.contains(id);
    final zebra = widget.zebra && index.isOdd;
    final interactive = widget.onRowTap != null;
    final columns = _columnsForSlice(columnSlice);

    Color backgroundFor({required bool hovered}) {
      if (selected) return colors.surfaceSelected;
      if (hovered) return colors.surfaceHover;
      if (zebra) return colors.surfaceMuted;
      return colors.surfaceDefault;
    }

    Widget buildCells() => Row(
      children: [
        if (_includeSelectionForSlice(columnSlice)) _selectionCell(id, selected),
        for (final column in columns) _buildDataCell(context, row, column, viewportWidth),
        if (_includeActionsForSlice(columnSlice)) _actionsCell(context, row),
      ],
    );

    Widget rowContent = DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundFor(hovered: false),
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: SizedBox(height: _density.rowHeight, child: buildCells()),
    );

    if (interactive) {
      rowContent = Focus(
        focusNode: _focusNodeForRow(index),
        onKeyEvent: (node, event) => _handleRowKeyEvent(node, event, row),
        child: AppFocusRing(
          visible: _focusNodeForRow(index).hasFocus,
          child: AppPressable.builder(
            onTap: () => widget.onRowTap!(row),
            borderRadius: BorderRadius.zero,
            builder: (context, states, child) {
              final hovered = states.contains(WidgetState.hovered);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundFor(hovered: hovered),
                  border: Border(bottom: BorderSide(color: colors.borderSubtle)),
                ),
                child: SizedBox(height: _density.rowHeight, child: buildCells()),
              );
            },
          ),
        ),
      );
    }

    return Semantics(selected: widget.selectable ? selected : null, child: rowContent);
  }

  Widget _selectionCell(String id, bool selected) {
    return SizedBox(
      width: _selectionColumnWidth,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.translucent,
          child: AppCheckbox(
            value: selected,
            onChanged: widget.onSelectionChanged == null ? null : (_) => _toggleRow(id),
            semanticLabel: 'Select row $id',
          ),
        ),
      ),
    );
  }

  Widget _actionsCell(BuildContext context, T row) {
    return SizedBox(
      width: _actionsColumnWidth,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.translucent,
          child:
              _buildRowActions(context, row) ??
              AppIconButton(
                icon: LucideIcons.moreHorizontal,
                semanticLabel: 'Row actions',
                size: AppIconButtonSize.sm,
                onPressed: () {},
              ),
        ),
      ),
    );
  }

  Widget _buildDataCell(BuildContext context, T row, AppTableColumn<T> column, double viewportWidth) {
    final typography = context.typography;
    final colors = context.colors;
    final width = _columnWidth(column, viewportWidth);
    final align = _alignmentFor(column.align);
    final useTabular = column.align == AppTableColumnAlign.end;
    final textStyle = useTabular ? typography.tabular(typography.bodySm) : typography.bodySm;

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _horizontalCellPadding,
          vertical: _verticalCellPadding,
        ),
        child: Align(
          alignment: align,
          child: DefaultTextStyle(
            style: textStyle.copyWith(color: colors.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            child: column.cellBuilder(context, row),
          ),
        ),
      ),
    );
  }

  Widget? _buildRowActions(BuildContext context, T row) {
    return widget.rowActions?.call(row);
  }

  Widget _buildFooter(BuildContext context, double viewportWidth) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: _horizontalCellPadding,
          vertical: _verticalCellPadding,
        ),
        child: DefaultTextStyle(
          style: context.typography.tabular(context.typography.bodySm).copyWith(color: colors.textSecondary),
          child: widget.footer!,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    if (widget.emptyState != null && !_filteredEmpty) {
      return widget.emptyState!;
    }
    if (widget.filteredEmptyState != null && _filteredEmpty) {
      return widget.filteredEmptyState!;
    }
    return AppEmptyState(variant: _filteredEmpty ? AppEmptyStateVariant.noResults : AppEmptyStateVariant.firstRun);
  }

  Widget _buildErrorState(BuildContext context) {
    if (widget.errorState != null) return widget.errorState!;
    return AppErrorState(
      message: widget.errorMessage ?? 'We could not load this content. Check your connection and try again.',
      onRetry: widget.onRetry,
    );
  }

  AlignmentGeometry _alignmentFor(AppTableColumnAlign align) => switch (align) {
    AppTableColumnAlign.start => AlignmentDirectional.centerStart,
    AppTableColumnAlign.center => Alignment.center,
    AppTableColumnAlign.end => AlignmentDirectional.centerEnd,
  };
}

enum _StickySliceMode { onlySticky, withoutSticky }

class _StickySlice {
  const _StickySlice({required this.mode, required this.stickyIndex});

  final _StickySliceMode mode;
  final int stickyIndex;
}

class _TableHeaderDelegate extends SliverPersistentHeaderDelegate {
  _TableHeaderDelegate({required this.rowHeight, required this.child});

  final double rowHeight;
  final Widget child;

  @override
  double get minExtent => rowHeight;

  @override
  double get maxExtent => rowHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(color: context.colors.surfaceMuted, child: child);
  }

  @override
  bool shouldRebuild(covariant _TableHeaderDelegate oldDelegate) =>
      oldDelegate.rowHeight != rowHeight || oldDelegate.child != child;
}

class _StackedField extends StatelessWidget {
  const _StackedField({required this.label, required this.value, required this.align});

  final String label;
  final Widget value;
  final AppTableColumnAlign align;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final crossAlign = switch (align) {
      AppTableColumnAlign.start => CrossAxisAlignment.start,
      AppTableColumnAlign.center => CrossAxisAlignment.center,
      AppTableColumnAlign.end => CrossAxisAlignment.end,
    };
    final valueStyle = align == AppTableColumnAlign.end ? typography.tabular(typography.body) : typography.body;

    return Column(
      crossAxisAlignment: crossAlign,
      children: [
        Text(label, style: typography.caption.copyWith(color: colors.textTertiary)),
        const SizedBox(height: AppSpacing.s1),
        DefaultTextStyle(
          style: valueStyle.copyWith(color: colors.textPrimary),
          child: value,
        ),
      ],
    );
  }
}
