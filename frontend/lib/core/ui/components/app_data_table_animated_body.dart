import 'package:flutter/material.dart';

import 'package:ai_clinic/core/ui/components/app_checkbox.dart';
import 'package:ai_clinic/core/ui/components/app_icon_button.dart';
import 'package:ai_clinic/core/ui/components/app_input_styles.dart';
import 'package:ai_clinic/core/ui/motion/app_motion.dart';
import 'package:ai_clinic/core/ui/theme/app_semantic_colors.dart';
import 'package:ai_clinic/core/ui/theme/app_spacing.dart';
import 'package:ai_clinic/core/ui/theme/app_typography.dart';

import 'app_data_table.dart';
import 'app_data_table_column_layout.dart';

const _maxEnterStagger = Duration(milliseconds: 120);
const _enterStaggerStep = Duration(milliseconds: 25);

/// Animated table body used when [AppDataTable.animateRows] is enabled.
///
/// Mirrors web `DataTable` `animateRows`: rows fade/slide in on insert, fade out
/// on removal, and slide vertically when reordered during filter/search updates.
class AppDataTableAnimatedBody<T> extends StatefulWidget {
  const AppDataTableAnimatedBody({required this.table, required this.buildRow, super.key});

  final AppDataTable<T> table;
  final Widget Function(BuildContext context, T item, int index, {Color? backgroundColor}) buildRow;

  @override
  State<AppDataTableAnimatedBody<T>> createState() => _AppDataTableAnimatedBodyState<T>();
}

class _RowSlot<T> {
  _RowSlot({
    required this.id,
    required this.item,
    required this.visualTop,
    this.entering = false,
    this.exiting = false,
  });

  final String id;
  T item;
  double visualTop;
  bool entering;
  bool exiting;
}

class _AppDataTableAnimatedBodyState<T> extends State<AppDataTableAnimatedBody<T>> with TickerProviderStateMixin {
  final List<_RowSlot<T>> _slots = [];
  final Map<String, AnimationController> _enterControllers = {};
  final Map<String, AnimationController> _exitControllers = {};

  AppDataTable<T> get table => widget.table;
  double get rowHeight => table.rowHeight;

  Duration get _motionDuration {
    final reduced = AppMotion.prefersReducedMotion(context);
    return AppMotion.resolveDuration(AppMotionPreset.rowEnter, reducedMotion: reduced);
  }

  Curve get _motionCurve {
    final reduced = AppMotion.prefersReducedMotion(context);
    return AppMotion.resolveCurve(AppMotionPreset.rowEnter, reducedMotion: reduced);
  }

  @override
  void initState() {
    super.initState();
    _seedSlots(widget.table.data, animate: false);
  }

  @override
  void didUpdateWidget(covariant AppDataTableAnimatedBody<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_rowsEqual(oldWidget.table.data, widget.table.data)) {
      _syncItemData(widget.table.data);
      return;
    }
    _applyDataChange(widget.table.data);
  }

  void _syncItemData(List<T> newData) {
    final itemsById = {for (final item in newData) widget.table.getRowId(item): item};
    setState(() {
      for (final slot in _slots) {
        final nextItem = itemsById[slot.id];
        if (nextItem != null) {
          slot.item = nextItem;
        }
      }
    });
  }

  bool _rowsEqual(List<T> a, List<T> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (widget.table.getRowId(a[i]) != widget.table.getRowId(b[i])) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    for (final controller in _enterControllers.values) {
      controller.dispose();
    }
    for (final controller in _exitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seedSlots(List<T> data, {required bool animate}) {
    _slots
      ..clear()
      ..addAll(
        data.asMap().entries.map(
          (entry) => _RowSlot<T>(
            id: table.getRowId(entry.value),
            item: entry.value,
            visualTop: entry.key * rowHeight,
            entering: animate,
          ),
        ),
      );
    if (animate) {
      for (var i = 0; i < _slots.length; i++) {
        _startEnter(_slots[i].id, i);
      }
    }
  }

  void _applyDataChange(List<T> newData) {
    final reduced = AppMotion.prefersReducedMotion(context);
    if (reduced) {
      setState(() => _seedSlots(newData, animate: false));
      return;
    }

    final newIds = newData.map(table.getRowId).toList();
    final newIdSet = newIds.toSet();
    final oldSlotsById = {
      for (final slot in _slots)
        if (!slot.exiting) slot.id: slot,
    };
    final oldIndexById = {for (var i = 0; i < _slots.length; i++) _slots[i].id: i};

    final nextSlots = <_RowSlot<T>>[];

    for (var index = 0; index < newData.length; index++) {
      final item = newData[index];
      final id = table.getRowId(item);
      final previous = oldSlotsById[id];
      final targetTop = index * rowHeight;

      if (previous == null) {
        nextSlots.add(_RowSlot<T>(id: id, item: item, visualTop: targetTop, entering: true));
        _startEnter(id, index);
      } else {
        previous
          ..item = item
          ..visualTop = targetTop
          ..entering = false;
        nextSlots.add(previous);
      }
    }

    for (final slot in _slots) {
      if (newIdSet.contains(slot.id) || slot.exiting) {
        continue;
      }
      final oldIndex = oldIndexById[slot.id] ?? 0;
      final exitingSlot = _RowSlot<T>(id: slot.id, item: slot.item, visualTop: oldIndex * rowHeight, exiting: true);
      final insertAt = oldIndex.clamp(0, nextSlots.length);
      nextSlots.insert(insertAt, exitingSlot);
      _startExit(slot.id);
    }

    setState(() {
      _slots
        ..clear()
        ..addAll(nextSlots);
    });
  }

  void _startEnter(String id, int index) {
    _enterControllers.remove(id)?.dispose();
    final delay = Duration(
      milliseconds: (index * _enterStaggerStep.inMilliseconds).clamp(0, _maxEnterStagger.inMilliseconds),
    );
    final controller = AnimationController(vsync: this, duration: _motionDuration);
    _enterControllers[id] = controller;
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) {
        return;
      }
      final slotIndex = _slots.indexWhere((slot) => slot.id == id);
      if (slotIndex == -1) {
        return;
      }
      setState(() {
        _slots[slotIndex].entering = false;
      });
    });
    if (delay == Duration.zero) {
      controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted && _enterControllers[id] == controller) {
          controller.forward();
        }
      });
    }
  }

  void _startExit(String id) {
    _exitControllers.remove(id)?.dispose();
    final controller = AnimationController(vsync: this, duration: AppMotion.quick);
    _exitControllers[id] = controller
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _removeExitingRow(id);
        }
      })
      ..forward();
  }

  void _removeExitingRow(String id) {
    if (!mounted) {
      return;
    }
    _exitControllers.remove(id)?.dispose();
    _enterControllers.remove(id)?.dispose();
    setState(() {
      _slots.removeWhere((slot) => slot.id == id && slot.exiting);
    });
  }

  Color? _rowBackground(int index, T item) {
    final colors = context.appColors;
    final selected = table.selectable && table.selectedIds.contains(table.getRowId(item));
    if (selected) {
      return colors.surfaceSelected;
    }
    final custom = table.rowBackgroundColor?.call(item, index);
    if (custom != null) {
      return custom;
    }
    if (table.zebra && index.isOdd) {
      return colors.surfaceMuted;
    }
    return null;
  }

  BoxBorder? _rowBorder(int index, T item) => table.rowBorder?.call(item, index);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final activeCount = _slots.where((slot) => !slot.exiting).length;
    final stackHeight = _slots.isEmpty
        ? activeCount * rowHeight
        : _slots.map((slot) => slot.visualTop).reduce((a, b) => a > b ? a : b) + rowHeight;

    return ClipRect(
      child: AnimatedSize(
        duration: _motionDuration,
        curve: _motionCurve,
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: stackHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var index = 0; index < _slots.length; index++)
                _buildAnimatedRow(context, _slots[index], index, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedRow(BuildContext context, _RowSlot<T> slot, int index, AppSemanticColors colors) {
    final enter = _enterControllers[slot.id];
    final exit = _exitControllers[slot.id];
    final direction = Directionality.of(context);
    final inlineEnter = direction == TextDirection.rtl ? 6.0 : -6.0;
    final dataIndex = (slot.visualTop / rowHeight).round();
    final background = _rowBackground(dataIndex, slot.item);
    final border = _rowBorder(dataIndex, slot.item);

    Widget row = widget.buildRow(context, slot.item, dataIndex, backgroundColor: background);

    if (border != null) {
      row = DecoratedBox(
        decoration: BoxDecoration(border: border),
        child: row,
      );
    }

    if (table.onRowClick != null) {
      row = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Material(
          color: background ?? Colors.transparent,
          child: InkWell(
            onTap: () => table.onRowClick!(slot.item),
            hoverColor: colors.surfaceHover,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            child: row,
          ),
        ),
      );
    } else if (background != null) {
      row = ColoredBox(color: background, child: row);
    }

    // Paint the row divider above the InkWell hover layer so it stays visible on hover.
    row = SizedBox(
      height: rowHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          row,
          Align(
            alignment: Alignment.bottomCenter,
            child: ColoredBox(
              color: colors.borderSubtle,
              child: const SizedBox(height: 1, width: double.infinity),
            ),
          ),
        ],
      ),
    );

    return AnimatedPositioned(
      key: ValueKey(slot.id),
      duration: _motionDuration,
      curve: _motionCurve,
      top: slot.visualTop,
      left: 0,
      right: 0,
      height: rowHeight,
      child: AnimatedBuilder(
        animation: Listenable.merge([?enter, ?exit]),
        builder: (context, child) {
          final enterT = slot.entering ? (enter?.value ?? 0) : 1.0;
          final exitT = slot.exiting ? (1 - (exit?.value ?? 0)) : 1.0;
          final opacity = enterT * exitT;
          final slideX = slot.entering ? inlineEnter * (1 - enterT) : 0.0;
          final slideY = slot.exiting ? -6.0 * (1 - exitT) : 0.0;

          return Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform.translate(offset: Offset(slideX, slideY), child: child),
          );
        },
        child: row,
      ),
    );
  }
}

/// Shared row layout for animated and grid table bodies.
Widget buildAppDataTableRowContent<T>({
  required BuildContext context,
  required AppDataTable<T> table,
  required T item,
  required int rowIndex,
  Color? backgroundColor,
  Map<String, double>? columnWidths,
  bool fillColumnExpanded = false,
}) {
  final colors = context.appColors;
  final cells = <Widget>[];
  final useFixedWidths = columnWidths != null;

  if (table.selectable) {
    final selectionCell = _buildSelectionCell(context, table, item, backgroundColor);
    cells.add(
      useFixedWidths
          ? SizedBox(width: AppDataTableColumnLayout.selectionColumnWidth, child: selectionCell)
          : Expanded(child: selectionCell),
    );
  }

  for (final column in table.columns) {
    final isFillColumn = fillColumnExpanded && AppDataTableColumnLayout.isFillColumn(table.columns, column.id);
    final width = isFillColumn ? null : (columnWidths?[column.id] ?? column.width);
    cells.add(
      layoutAppDataTableColumn(
        width: width,
        fill: isFillColumn,
        child: _buildDataCell(
          context: context,
          align: column.align,
          backgroundColor: backgroundColor,
          child: DefaultTextStyle(
            style: AppTypography.bodySm(context).copyWith(color: colors.textPrimary),
            textAlign: _textAlign(column.align),
            child: column.accessor(item),
          ),
        ),
      ),
    );
  }

  if (table.rowActions != null) {
    cells.add(
      SizedBox(
        width: AppDataTableColumnLayout.actionsColumnWidth,
        child: _buildActionsCell(context, table, item, backgroundColor),
      ),
    );
  }

  return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells);
}

TextAlign _textAlign(TableAlign align) => switch (align) {
  TableAlign.start => TextAlign.start,
  TableAlign.end => TextAlign.end,
  TableAlign.center => TextAlign.center,
};

Alignment _cellAlignment(TableAlign align) => switch (align) {
  TableAlign.start => Alignment.centerLeft,
  TableAlign.end => Alignment.centerRight,
  TableAlign.center => Alignment.center,
};

Widget _buildDataCell({
  required BuildContext context,
  required TableAlign align,
  required Widget child,
  Color? backgroundColor,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: AppSpacing.space3),
}) {
  return ColoredBox(
    color: backgroundColor ?? Colors.transparent,
    child: Container(alignment: _cellAlignment(align), padding: padding, child: child),
  );
}

Widget _buildSelectionCell<T>(BuildContext context, AppDataTable<T> table, T item, Color? backgroundColor) {
  final id = table.getRowId(item);
  final selected = table.selectedIds.contains(id);

  return _buildDataCell(
    context: context,
    align: TableAlign.center,
    backgroundColor: backgroundColor,
    child: appWrapMaterialInput(
      AppCheckbox(
        value: selected ? AppCheckboxState.checked : AppCheckboxState.unchecked,
        onChanged: table.onSelectionChange == null
            ? null
            : (_) {
                final onChange = table.onSelectionChange;
                if (onChange == null) {
                  return;
                }
                final next = Set<String>.from(table.selectedIds);
                if (next.contains(id)) {
                  next.remove(id);
                } else {
                  next.add(id);
                }
                onChange(next);
              },
      ),
    ),
  );
}

Widget _buildActionsCell<T>(BuildContext context, AppDataTable<T> table, T item, Color? backgroundColor) {
  return _buildDataCell(
    context: context,
    align: TableAlign.center,
    backgroundColor: backgroundColor,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
    child:
        table.rowActions!(item) ??
        AppIconButton(
          icon: const Icon(Icons.more_horiz, size: 16),
          label: 'Row actions',
          size: AppIconButtonSize.sm,
          onPressed: () {},
        ),
  );
}
