import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'app_data_table.dart';

/// Column width math and persistence for [AppDataTable].
abstract final class AppDataTableColumnLayout {
  AppDataTableColumnLayout._();

  static const double defaultMinColumnWidth = 72;
  static const double selectionColumnWidth = 40;
  static const double actionsColumnWidth = 48;
  static const double resizeHandleWidth = 8;

  static String storageKeyFor(String key) => 'app_data_table:column_widths:$key';

  /// Last data column fills remaining table width when resizing is enabled.
  static bool isFillColumn<T>(List<TableColumn<T>> columns, String columnId) {
    return columns.isNotEmpty && columns.last.id == columnId;
  }

  static List<TableColumn<T>> storedColumns<T>(List<TableColumn<T>> columns) {
    if (columns.length <= 1) {
      return const [];
    }
    return columns.sublist(0, columns.length - 1);
  }

  static String? fillColumnId<T>(List<TableColumn<T>> columns) {
    if (columns.isEmpty) {
      return null;
    }
    return columns.last.id;
  }

  static Future<Map<String, double>?> loadPersistedWidths(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKeyFor(key));
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }

    final widths = <String, double>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (entry.key is String && value is num) {
        widths[entry.key as String] = value.toDouble();
      }
    }
    return widths.isEmpty ? null : widths;
  }

  static Future<void> persistWidths(String key, Map<String, double> widths) async {
    if (widths.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(widths.map((columnId, width) => MapEntry(columnId, width)));
    await prefs.setString(storageKeyFor(key), encoded);
  }

  static Map<String, double> initialWidths<T>({
    required List<TableColumn<T>> columns,
    required double availableWidth,
    required bool selectable,
    required bool hasRowActions,
    Map<String, double>? persisted,
    double minColumnWidth = defaultMinColumnWidth,
  }) {
    final result = <String, double>{};
    final layoutColumns = storedColumns(columns);
    if (layoutColumns.isEmpty) {
      return result;
    }

    final fillColumn = columns.last;
    final fillMinWidth = fillColumn.minWidth ?? minColumnWidth;
    final hasExplicitWidths = layoutColumns.any((column) => column.width != null);

    if (persisted != null) {
      for (final column in layoutColumns) {
        final stored = persisted[column.id];
        if (stored != null) {
          result[column.id] = _clampWidth(stored, minWidth: column.minWidth ?? minColumnWidth);
        }
      }
    }

    final reservedWidth = (selectable ? selectionColumnWidth : 0) + (hasRowActions ? actionsColumnWidth : 0);
    var remaining = math.max(availableWidth - reservedWidth - result.values.fold(0.0, (a, b) => a + b), 0);

    final pending = layoutColumns.where((column) => !result.containsKey(column.id)).toList(growable: false);
    if (pending.isEmpty) {
      return result;
    }

    final explicit = pending.where((column) => column.width != null).toList(growable: false);
    final flexible = pending.where((column) => column.width == null).toList(growable: false);

    for (final column in explicit) {
      final width = _clampWidth(column.width!, minWidth: column.minWidth ?? minColumnWidth);
      result[column.id] = width;
      remaining = math.max(0, remaining - width);
    }

    if (flexible.isEmpty) {
      return result;
    }

    if (hasExplicitWidths) {
      final share = math.max(minColumnWidth, remaining / (flexible.length + 1));
      for (final column in flexible) {
        result[column.id] = _clampWidth(share, minWidth: column.minWidth ?? minColumnWidth);
      }
      return result;
    }

    remaining = math.max(0, remaining - fillMinWidth);
    final share = math.max(minColumnWidth, remaining / flexible.length);
    for (final column in flexible) {
      result[column.id] = _clampWidth(share, minWidth: column.minWidth ?? minColumnWidth);
    }

    return result;
  }

  static Map<String, double> resizeColumn<T>({
    required Map<String, double> widths,
    required List<TableColumn<T>> columns,
    required String columnId,
    required double delta,
    double minColumnWidth = defaultMinColumnWidth,
  }) {
    TableColumn<T>? column;
    for (final entry in columns) {
      if (entry.id == columnId) {
        column = entry;
        break;
      }
    }
    if (column == null || !column.resizable || isFillColumn(columns, columnId)) {
      return widths;
    }

    final minWidth = column.minWidth ?? minColumnWidth;
    final current = widths[columnId] ?? minWidth;
    return {...widths, columnId: _clampWidth(current + delta, minWidth: minWidth)};
  }

  static double minimumTableWidth<T>({
    required List<TableColumn<T>> columns,
    required Map<String, double> widths,
    required bool selectable,
    required bool hasRowActions,
    double minColumnWidth = defaultMinColumnWidth,
  }) {
    var total = selectable ? selectionColumnWidth : 0.0;
    total += hasRowActions ? actionsColumnWidth : 0.0;
    for (final column in columns) {
      if (isFillColumn(columns, column.id)) {
        total += column.minWidth ?? minColumnWidth;
      } else {
        total += widths[column.id] ?? column.width ?? minColumnWidth;
      }
    }
    return total;
  }

  static double totalWidth<T>({
    required List<TableColumn<T>> columns,
    required Map<String, double> widths,
    required bool selectable,
    required bool hasRowActions,
    double minColumnWidth = defaultMinColumnWidth,
  }) {
    var total = selectable ? selectionColumnWidth : 0.0;
    total += hasRowActions ? actionsColumnWidth : 0.0;
    for (final column in columns) {
      total += widths[column.id] ?? column.width ?? minColumnWidth;
    }
    return total;
  }

  static Map<String, double> pruneToColumns<T>({
    required Map<String, double> widths,
    required List<TableColumn<T>> columns,
  }) {
    final fillId = fillColumnId(columns);
    final knownIds = storedColumns(columns).map((column) => column.id).toSet();
    return {
      for (final entry in widths.entries)
        if (knownIds.contains(entry.key) && entry.key != fillId) entry.key: entry.value,
    };
  }

  static double _clampWidth(double width, {required double minWidth}) => math.max(minWidth, width);
}
